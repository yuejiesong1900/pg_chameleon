--create schema
CREATE SCHEMA IF NOT EXISTS sch_chameleon;

CREATE OR REPLACE VIEW sch_chameleon.v_version 
 AS
	SELECT '1.0'::TEXT t_version
;


CREATE TYPE sch_chameleon.en_src_status
	AS ENUM ('ready', 'initialising','initialised','stopped','running');

CREATE TYPE sch_chameleon.en_binlog_event 
	AS ENUM ('delete', 'update', 'insert','ddl');

	
CREATE TABLE sch_chameleon.t_sources
(
	i_id_source	bigserial,
	t_source		text NOT NULL,
	t_dest_schema   text NOT NULL,
	enm_status sch_chameleon.en_src_status NOT NULL DEFAULT 'ready',
	ts_last_event timestamp without time zone,
	CONSTRAINT pk_t_sources PRIMARY KEY (i_id_source)
)
;

CREATE UNIQUE INDEX idx_t_sources_t_source ON sch_chameleon.t_sources(t_source);
CREATE UNIQUE INDEX idx_t_sources_t_dest_schema ON sch_chameleon.t_sources(t_dest_schema);


CREATE TABLE sch_chameleon.t_replica_batch
(
  i_id_batch bigserial NOT NULL,
  i_id_source bigint NOT NULL,
  t_binlog_name text,
  i_binlog_position integer,
  b_started boolean NOT NULL DEFAULT False,
  b_processed boolean NOT NULL DEFAULT False,
  b_replayed boolean NOT NULL DEFAULT False,
  ts_created timestamp without time zone NOT NULL DEFAULT clock_timestamp(),
  ts_processed timestamp without time zone ,
  ts_replayed timestamp without time zone ,
  v_log_table character varying(100) NOT NULL,
  i_replayed bigint NULL,
  i_skipped bigint NULL,
  i_ddl bigint NULL,
  CONSTRAINT pk_t_batch PRIMARY KEY (i_id_batch)
)
WITH (
  OIDS=FALSE
);

CREATE UNIQUE INDEX idx_t_replica_batch_binlog_name_position 
    ON sch_chameleon.t_replica_batch  (i_id_source,t_binlog_name,i_binlog_position);

CREATE UNIQUE INDEX idx_t_replica_batch_ts_created
	ON sch_chameleon.t_replica_batch (i_id_source,ts_created);

CREATE TABLE IF NOT EXISTS sch_chameleon.t_log_replica
(
  i_id_event bigserial NOT NULL,
  i_id_batch bigserial NOT NULL,
  v_table_name character varying(100) NOT NULL,
  v_schema_name character varying(100) NOT NULL,
  enm_binlog_event sch_chameleon.en_binlog_event NOT NULL,
  t_binlog_name text,
  i_binlog_position integer,
  ts_event_datetime timestamp without time zone NOT NULL DEFAULT clock_timestamp(),
  jsb_event_data jsonb,
  jsb_event_update jsonb,
   t_query TEXT NULL,
  CONSTRAINT pk_log_replica PRIMARY KEY (i_id_event),
  CONSTRAINT fk_replica_batch FOREIGN KEY (i_id_batch) 
	REFERENCES  sch_chameleon.t_replica_batch (i_id_batch)
	ON UPDATE RESTRICT ON DELETE CASCADE
)
WITH (
  OIDS=FALSE
);

CREATE TABLE IF NOT EXISTS sch_chameleon.t_log_replica_1 
(
CONSTRAINT pk_log_replica_1 PRIMARY KEY (i_id_event),
  CONSTRAINT fk_replica_batch_1 FOREIGN KEY (i_id_batch) 
	REFERENCES  sch_chameleon.t_replica_batch (i_id_batch)
	ON UPDATE RESTRICT ON DELETE CASCADE
)
INHERITS (sch_chameleon.t_log_replica)
;

CREATE TABLE IF NOT EXISTS sch_chameleon.t_log_replica_2
(
CONSTRAINT pk_log_replica_2 PRIMARY KEY (i_id_event),
  CONSTRAINT fk_replica_batch_2 FOREIGN KEY (i_id_batch) 
	REFERENCES  sch_chameleon.t_replica_batch (i_id_batch)
	ON UPDATE RESTRICT ON DELETE CASCADE
)
INHERITS (sch_chameleon.t_log_replica)
;

CREATE TABLE sch_chameleon.t_replica_tables
(
  i_id_table bigserial NOT NULL,
  i_id_source bigint NOT NULL,
  v_table_name character varying(100) NOT NULL,
  v_schema_name character varying(100) NOT NULL,
  v_table_pkey character varying(100)[] NOT NULL,
  CONSTRAINT pk_t_replica_tables PRIMARY KEY (i_id_table)
)
WITH (
  OIDS=FALSE
);

CREATE UNIQUE INDEX idx_t_replica_tables_table_schema
	ON sch_chameleon.t_replica_tables (i_id_source,v_table_name,v_schema_name);


CREATE TABLE sch_chameleon.t_discarded_rows
(
	i_id_row		bigserial,
	i_id_batch	bigint NOT NULL,
	ts_discard	timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
	t_row_data	text,
	CONSTRAINT pk_t_discarded_rows PRIMARY KEY (i_id_row)
)
;
	
	
ALTER TABLE sch_chameleon.t_replica_batch
	ADD CONSTRAINT fk_t_replica_batch_i_id_source FOREIGN KEY (i_id_source)
	REFERENCES sch_chameleon.t_sources (i_id_source)
	ON UPDATE RESTRICT ON DELETE CASCADE
	;

ALTER TABLE sch_chameleon.t_replica_tables
	ADD CONSTRAINT fk_t_replica_tables_i_id_source FOREIGN KEY (i_id_source)
	REFERENCES sch_chameleon.t_sources (i_id_source)
	ON UPDATE RESTRICT ON DELETE CASCADE
	;



CREATE TABLE sch_chameleon.t_index_def
(
  i_id_def bigserial NOT NULL,
  i_id_source bigint NOT NULL,
  v_schema character varying(100),
  v_table character varying(100),
  v_index character varying(100),
  t_create	text,
  t_drop	text,
  CONSTRAINT pk_t_index_def PRIMARY KEY (i_id_def)
)
WITH (
  OIDS=FALSE
);

CREATE UNIQUE INDEX idx_schema_table_source ON sch_chameleon.t_index_def(i_id_source,v_schema,v_table,v_index);
	
	
CREATE OR REPLACE FUNCTION sch_chameleon.fn_process_batch(integer,integer)
RETURNS BOOLEAN AS
$BODY$
	DECLARE
	    p_i_max_events	ALIAS FOR $1;
		p_i_source_id   ALIAS FOR $2;
		v_r_rows	    record;
		v_t_fields	    text[];
		v_t_values	    text[];
		v_t_sql_rep	    text;
		v_t_pkey	    text;
		v_t_vals	    text;
		v_t_update	    text;
		v_t_ins_fld	    text;
		v_t_ins_val	    text;
		v_t_ddl		    text;
		v_b_loop	    boolean;
		v_i_id_batch	integer;
		v_i_replayed integer;
		v_i_skipped integer;
		
	BEGIN
	    v_b_loop:=True;
		v_i_replayed=0;
		FOR v_r_rows IN WITH t_batch AS
					(
						SELECT 
							i_id_batch 
						FROM ONLY
							sch_chameleon.t_replica_batch  
						WHERE 
								    b_started 
							AND 	b_processed 
							AND     NOT b_replayed
							AND     i_id_source=p_i_source_id
						ORDER BY 
							ts_created 
						LIMIT 1
					),
				t_events AS
					(
						SELECT 
						    log.i_id_event,
							bat.i_id_batch,
							log.v_table_name,
							log.v_schema_name,
							log.enm_binlog_event,
							log.jsb_event_data,
							log.jsb_event_update,
							log.t_query,
							tab.v_table_pkey as v_pkey_where,
							replace(array_to_string(tab.v_table_pkey,','),'"','') as t_pkeys,
							array_length(tab.v_table_pkey,1) as i_pkeys
						FROM 
							sch_chameleon.t_log_replica  log
							INNER JOIN sch_chameleon.t_replica_tables tab
								ON
										tab.v_table_name=log.v_table_name
									AND tab.v_schema_name=log.v_schema_name
									AND tab.i_id_source=p_i_source_id
								INNER JOIN t_batch bat
								ON	bat.i_id_batch=log.i_id_batch
							
						ORDER BY ts_event_datetime
						LIMIT p_i_max_events
					)
				SELECT
				    i_id_event,
					i_id_batch,
					v_table_name,
					v_schema_name,
					enm_binlog_event,
					jsb_event_data,
					jsb_event_update,
					t_query,
					string_to_array(t_pkeys,',') as v_table_pkey,
					array_to_string(v_pkey_where,',') as v_pkey_where,
					t_pkeys,
					i_pkeys
				FROM
					t_events
			LOOP
			
			IF v_r_rows.enm_binlog_event='ddl'
			THEN
				v_t_ddl=format('SET search_path=%I;%s',v_r_rows.v_schema_name,v_r_rows.t_query);
			    RAISE DEBUG 'DDL: %',v_t_ddl;
			    EXECUTE  v_t_ddl;
			    DELETE FROM sch_chameleon.t_log_replica
			    WHERE
				    i_id_event=v_r_rows.i_id_event
			    ;
				UPDATE ONLY sch_chameleon.t_replica_batch  
				SET 
					i_ddl=coalesce(i_ddl,0)+1
				WHERE
					i_id_batch=v_r_rows.i_id_batch
				;
            ELSE
    			SELECT 
    				array_agg(key) evt_fields,
    				array_agg(value) evt_values
    				INTO
    					v_t_fields,
    					v_t_values
    			FROM (
    				SELECT 
    					key ,
    					value
    				FROM 
    					jsonb_each_text(v_r_rows.jsb_event_data) js_event
    			     ) js_dat
    			;
    
    			
    			WITH 	t_jsb AS
    				(
    					SELECT 
							CASE
								WHEN v_r_rows.enm_binlog_event='update'
								THEN 
									v_r_rows.jsb_event_update
							ELSE
								v_r_rows.jsb_event_data 
							END jsb_event_data ,
    						v_r_rows.v_table_pkey v_table_pkey
    				),
    				t_subscripts AS
    				(
    					SELECT 
    						generate_subscripts(v_table_pkey,1) sub
    					FROM 
    						t_jsb
    				)
    			SELECT 
    				array_to_string(v_table_pkey,','),
    				''''||array_to_string(array_agg((jsb_event_data->>v_table_pkey[sub])::text),''',''')||'''' as pk_value
    				INTO 
    					v_t_pkey,
    					v_t_vals
    
    			FROM
    				t_subscripts,t_jsb
    			GROUP BY v_table_pkey
    			;
    			
    			RAISE DEBUG '% % % % % %',v_r_rows.v_table_name,
    					v_r_rows.v_schema_name,
    					v_r_rows.v_table_pkey,
    					v_r_rows.enm_binlog_event,v_t_fields,v_t_values;
    			IF v_r_rows.enm_binlog_event='delete'
    			THEN
    				v_t_sql_rep=format('DELETE FROM %I.%I WHERE (%s)=(%s) ;',
    							v_r_rows.v_schema_name,
    							v_r_rows.v_table_name,
    							v_r_rows.v_pkey_where,
    							v_t_vals
    						);
    				RAISE DEBUG '%',v_t_sql_rep;
    			ELSEIF v_r_rows.enm_binlog_event='update'
    			THEN 
    				SELECT 
    					array_to_string(array_agg(format('%I=%L',t_field,t_value)),',') 
    					INTO
    						v_t_update
    				FROM
    				(
    					SELECT 
    						unnest(v_t_fields) t_field, 
    						unnest(v_t_values) t_value
    				) t_val
    				;
    
    				v_t_sql_rep=format('UPDATE  %I.%I 
    								SET
    									%s
    							WHERE (%s)=(%s) ;',
    							v_r_rows.v_schema_name,
    							v_r_rows.v_table_name,
    							v_t_update,
    							v_r_rows.v_pkey_where,
    							v_t_vals
    						);
    				RAISE DEBUG '%',v_t_sql_rep;
    			ELSEIF v_r_rows.enm_binlog_event='insert'
    			THEN
    				SELECT 
    					array_to_string(array_agg(format('%I',t_field)),',') t_field,
    					array_to_string(array_agg(format('%L',t_value)),',') t_value
    					INTO
    						v_t_ins_fld,
    						v_t_ins_val
    				FROM
    				(
    					SELECT 
    						unnest(v_t_fields) t_field, 
    						unnest(v_t_values) t_value
    				) t_val
    				;
    				v_t_sql_rep=format('INSERT INTO  %I.%I 
    								(
    									%s
    								)
    							VALUES
    								(
    									%s
    								)
    							;',
    							v_r_rows.v_schema_name,
    							v_r_rows.v_table_name,
    							v_t_ins_fld,
    							v_t_ins_val
    							
    						);
    
    				RAISE DEBUG '%',v_t_sql_rep;
    			END IF;
    			EXECUTE v_t_sql_rep;
    			
    			DELETE FROM sch_chameleon.t_log_replica
    		    WHERE
    			    i_id_event=v_r_rows.i_id_event
    		    ;
				v_i_replayed=v_i_replayed+1;
				v_i_id_batch=v_r_rows.i_id_batch;
				
            END IF;
		END LOOP;
		IF v_i_replayed>0
		THEN
			UPDATE ONLY sch_chameleon.t_replica_batch  
			SET 
				i_replayed=v_i_replayed,
				ts_replayed=clock_timestamp()
				
			WHERE
				i_id_batch=v_i_id_batch
			;
		END IF;
		
		IF v_r_rows IS NULL
		THEN 
		    RAISE DEBUG 'v_r_rows: %',v_r_rows.i_id_event; 
		    v_b_loop=False;
		    
		
		UPDATE ONLY sch_chameleon.t_replica_batch  
			SET 
				b_replayed=True,
				ts_replayed=clock_timestamp()
				
		WHERE
			i_id_batch=(
    			            SELECT 
    							i_id_batch 
    						FROM ONLY
    							sch_chameleon.t_replica_batch  
    						WHERE 
    								b_started 
    							AND 	b_processed 
    							AND     NOT b_replayed
    						ORDER BY 
    							ts_created 
    						LIMIT 1
						)
		RETURNING i_id_batch INTO v_i_id_batch
		;

		DELETE FROM sch_chameleon.t_log_replica
    		    WHERE
    			    i_id_batch=v_i_id_batch
    		    ;
				
		GET DIAGNOSTICS v_i_skipped = ROW_COUNT;
		UPDATE ONLY sch_chameleon.t_replica_batch  
			SET 
				i_skipped=v_i_skipped
			WHERE
				i_id_batch=v_i_id_batch
			;
		SELECT 
			count(*)>0 
			INTO
				v_b_loop
		FROM ONLY
			sch_chameleon.t_replica_batch  
		WHERE 
				b_started 
			AND 	b_processed 
			AND     NOT b_replayed
		;

		END IF;
		
        RETURN v_b_loop	;
	END;
$BODY$
LANGUAGE plpgsql;
