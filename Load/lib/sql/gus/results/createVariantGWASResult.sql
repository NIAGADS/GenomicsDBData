-- table for variant gwas result
DROP TABLE IF EXISTS Results.VariantGWAS;
DROP SEQUENCE IF EXISTS Results.VariantGWAS_SQ;

CREATE TABLE Results.VariantGWAS (
       VARIANT_GWAS_ID	     	 BIGSERIAL PRIMARY KEY,
       PROTOCOL_APP_NODE_ID	     NUMERIC(12) NOT NULL,
       VARIANT_RECORD_PRIMARY_KEY	     TEXT NOT NULL,
       BIN_INDEX		     LTREE,
       NEG_LOG10_PVALUE	     	     FLOAT NOT NULL,
       PVALUE_DISPLAY		     CHARACTER VARYING(25) NOT NULL, -- scientific notation
       FREQUENCY		     FLOAT,
       ALLELE			     TEXT,
       RESTRICTED_STATS		     JSONB,

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
);


-- CONSTRAINTS

--ALTER TABLE Results.VariantGWAS ADD CONSTRAINT CONST_VGWAS_PROTOCOL_APP_NODE_ID FOREIGN KEY (protocol_app_node_id) REFERENCES Study.ProtocolAppNode (protocol_app_node_id);

-- INDEXES

CREATE INDEX GWAS_RESULT_PAN_BRIN ON Results.VariantGWAS USING BRIN(PROTOCOL_APP_NODE_ID);

-- GRANTS

GRANT SELECT ON Results.VariantGWAS TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON Results.VariantGWAS TO gus_w;

-- SEQUENCES

CREATE SEQUENCE Results.VariantGWAS_SQ;
GRANT SELECT ON Results.VariantGWAS_SQ TO gus_w;
GRANT SELECT ON Results.VariantGWAS_SQ TO gus_r;

-- GUS CORE

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'VariantGWAS',
       'Standard', 'VARIANT_GWAS_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'Results') d
WHERE 'VariantGWAS' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

