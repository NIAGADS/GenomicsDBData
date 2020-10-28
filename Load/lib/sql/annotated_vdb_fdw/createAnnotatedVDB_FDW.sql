-- first execute the following run the following on the AnnotatedVDB
/* 
GRANT USAGE ON SCHEMA public TO <user>;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO <user>;

*/ 

-- create database links to user database in app database
-- "<dbuser>", "<dbpassword>", "<port>", and "<dbversion>" must be replaced by the actual values before this is run

DROP SCHEMA IF EXISTS AnnotatedVDB;


CREATE SERVER annotated_vdb
        FOREIGN DATA WRAPPER postgres_fdw
        OPTIONS (HOST 'localhost', port '5437', dbname 'annotated_vdb', use_remote_estimate 'True');

CREATE USER MAPPING FOR <user>
        SERVER annotated_vdb
        OPTIONS (user '<user>', password '<pwd>');


CREATE SCHEMA AnnotatedVDB;


IMPORT FOREIGN SCHEMA PUBLIC -- LIMIT TO (BinIndexRef, Variant)
    FROM SERVER annotated_vdb INTO AnnotatedVDB;

GRANT SELECT ON AnnotatedVDB.BinIndexRef TO COMM_WDK_W;
GRANT SELECT ON AnnotatedVDB.Variant TO COMM_WDK_W;
GRANT INSERT,UPDATE,DELETE,SELECT ON AnnotatedVDB.Variant TO gus_w;
GRANT INSERT,UPDATE,DELETE,SELECT ON AnnotatedVDB.AlgorithmInvocation TO gus_w;
