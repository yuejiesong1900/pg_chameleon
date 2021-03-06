changelog 
*************************

1.0 RC1  -  15 Apr 2017
............................................
* add support for primay key defined as column constraint
* fix regression if null constraint is omitted in a primary key column
* add foreign key generation to detach replica. keys are added invalid and a validation attempt is performed.
* add support for truncate table 
* add parameter out_dir to set the output destination for the csv files during init_replica
* add set tables_only  to table_limit when streaming the mysql replica
* force a close batch on rotate event if binlog changes without any row events collected
* fixed replica regression with python 3.x and empty binary data
* added event_update in hexlify strategy
* add tabulate for nice display for sources/status
* logs are rotated on a daily basis
* removed parameter log_append 
* add parameter log_days_keep to specify how many days keep the logs
* feature freeze


1.0 Beta 2  -  02 Apr 2017
............................................
* add detach replica with automatic sequence reset (no FK generation yet)
* replica speed improvement with the exclusion  of BEGIN,COMMIT when capturing the queries from MySQL
* fix the capturing regexp  for primary keys and foreign keys
* fix version in documentation 


1.0 Beta 1  -  18 Mar 2017
............................................
* changed not python files in package  to work properly with system wide installations
* fixed issue with ALTER TABLE ADD CONSTRAINT
* add datetime.timedelta to json encoding exceptions
* added support for enum in ALTER TABLE MODIFY
* requires psycopg2 2.7 which installs without postgresql headers



1.0 Alpha 4  -  28 Feb 2017
............................................

* Add batch retention to avoid bloating of t_replica_batch
* Packaged for pip, now you can install the replica tool in a virtual env just typing pip install pg_chameleon


1.0 Alpha 3  -  7 Feb 2017
............................................


* Basic DDL Support (CREATE/DROP/ALTER TABLE, DROP PRIMARY KEY)
* Replica from multiple MySQL schema or servers
* Python 3 support


1.0 Alpha 2  -  31 Dec 2016 
............................................

Changelog from alpha 1

* Several fixes in the DDL replica and add support for CHANGE statement.
* Add support for check if process is running already, in order to avoid two replica processes run at the same time.
* Port to python 3.6. This is still experimental. Any feedback is more than welcome.




1.0 Alpha 1  -  27 Nov 2016
............................................

Installation in virtualenv

For working properly you should use virtualenv for installing the requirements via pip
No daemon yet

The script should be executed in a screen session to keep it running. Currently there's no respawning of the process on failure nor failure detector.
psycopg2 requires python and postgresql dev files

The psycopg2's pip installation requires the python development files and postgresql source code.
Please refer to your distribution for fulfilling those requirements.
DDL replica limitations

DDL and DML mixed in the same transaction are not decoded in the right order. This can result in a replica breakage caused by a wrong jsonb descriptor if the DML change the data on the same table modified by the DDL. I know the issue and I'm working on a solution.
Test please!

Please submit the issues you find.
Bear in mind this is an alpha release. if you use the software in production keep an eye on the process to ensure the data is correctly replicated.
