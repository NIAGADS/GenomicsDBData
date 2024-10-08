-- table for merged variants
DROP TABLE IF EXISTS NIAGADS.UniProtEntityMap;
DROP SEQUENCE IF EXISTS NIAGADS.UniProtEntityMap_SQ;

CREATE TABLE NIAGADS.UniProtEntityMap  (
       UNIPROT_ENTITY_ID	SERIAL PRIMARY KEY,
       UNIPROT_ID		CHARACTER VARYING (25) NOT NULL,
       DATABASE			CHARACTER VARYING (20) NOT NULL,	
       MAPPED_ID		CHARACTER VARYING (50) NOT NULL,
       EXTERNAL_DATABASE_RELEASE_ID	  NUMERIC(12) NOT NULL,
       -- GUS HOUSEKEEPING

       MODIFICATION_DATE	 DATE,
       USER_READ		 NUMERIC(1),
       USER_WRITE		 NUMERIC(1),
       GROUP_READ		 NUMERIC(10),
       GROUP_WRITE 		 NUMERIC(1),
       OTHER_READ		 NUMERIC(1),
       OTHER_WRITE		 NUMERIC(1),
       ROW_USER_ID		 NUMERIC(12),
       ROW_GROUP_ID		 NUMERIC(4),
       ROW_PROJECT_ID		 NUMERIC(4),
       ROW_ALG_INVOCATION_ID	 NUMERIC(12)
       -- CONSTRAINT UPEM_XDBR FOREIGN KEY (external_database_release_id) REFERENCES SRes.ExternalDatabaseRelease(external_database_release_id)
);

-- INDEXES

-- see tuning_indexes directory

-- GRANTS

GRANT SELECT ON NIAGADS.UniProtEntityMap TO gus_r;
GRANT SELECT ON NIAGADS.UniProtEntityMap TO Comm_wdk_w;
GRANT INSERT, SELECT, UPDATE, DELETE ON NIAGADS.UniProtEntityMap TO gus_w;

-- SEQUENCES

CREATE SEQUENCE NIAGADS.UniProtEntityMap_SQ;
GRANT SELECT ON NIAGADS.UniProtEntityMap_SQ TO gus_w;
GRANT SELECT ON NIAGADS.UniProtEntityMap_SQ TO gus_r;

-- GUS CORE

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'UniProtEntityMap',
       'Standard', 'UNIPROT_ENTITY_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'NIAGADS') d
WHERE 'UniProtEntityMap' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

