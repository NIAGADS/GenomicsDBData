-- Dataset Presenter "Schema"

DROP TABLE IF EXISTS CBIL.DatasetModelRef;
DROP SEQUENCE IF EXISTS CBIL.DatasetModelRef_SQ;

CREATE TABLE CBIL.DatasetModelRef (
       DATASET_MODEL_REF_ID         SERIAL PRIMARY KEY,
       ACCESSION         	    VARCHAR(100) NOT NULL,
       RECORD_TYPE                  VARCHAR(100),
       TARGET_TYPE                  VARCHAR(20),
       TARGET_NAME                  VARCHAR(300),

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
);

CREATE SEQUENCE CBIL.DatasetModelRef_SQ;

GRANT SELECT ON CBIL.DatasetModelRef TO gus_r;
GRANT SELECT ON CBIL.DatasetModelRef TO comm_wdk_w;
GRANT SELECT ON CBIL.DatasetModelRef_SQ TO comm_wdk_w;

GRANT SELECT, UPDATE, INSERT, DELETE ON CBIL.DatasetModelRef TO gus_w;
GRANT SELECT ON CBIL.DatasetModelRef_SQ TO gus_w;

CREATE INDEX DMR_INDO1 ON CBIL.DatasetModelRef(accession);
CREATE INDEX DMR_INDO2 ON CBIL.DatasetModelRef(target_name, accession);
CREATE INDEX DMR_INDO3 ON CBIL.DatasetModelRef(record_type, target_type, target_name, accession);

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'DatasetModelRef',
       'Standard', 'DATASET_MODEL_REF_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'CBIL') d
WHERE 'DatasetModelRef' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);
