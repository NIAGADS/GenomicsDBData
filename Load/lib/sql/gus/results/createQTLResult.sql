-- table for variant gwas result
DROP TABLE IF EXISTS Results.QTL;
DROP SEQUENCE IF EXISTS Results.QTL_SQ;

CREATE TABLE Results.QTL (
        QTL_ID	     	 BIGSERIAL PRIMARY KEY,
        PROTOCOL_APP_NODE_ID	     NUMERIC(12) NOT NULL,
        CHROMOSOME   CHARACTER VARYING(10) NOT NULL,
        POSITION INTEGER NOT NULL,
        VARIANT_RECORD_PRIMARY_KEY	     TEXT NOT NULL,
        BIN_INDEX		     LTREE,
        TEST_ALLELE                TEXT NOT NULL,
        NEG_LOG10_PVALUE	     	     FLOAT NOT NULL,
        PVALUE_DISPLAY		     CHARACTER VARYING(25) NOT NULL, -- scientific notation
        DIST_TO_TARGET       INTEGER,
        TARGET_ENSEMBL_ID     CHARACTER VARYING(50) NOT NULL,
        OTHER_STATS		     JSONB,
        RANK INTEGER NOT NULL,

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

--ALTER TABLE Results.QTL ADD CONSTRAINT CONST_QTL_PROTOCOL_APP_NODE_ID FOREIGN KEY (protocol_app_node_id) REFERENCES Study.ProtocolAppNode (protocol_app_node_id);
--ALTER TABLE Results.QTL ADD CONSTRAINT CONST_QTL_TARGET_ID FOREIGN KEY (target_id) REFERENCES DOTS.Gene (source_id);

-- INDEXES

CREATE INDEX QTL_RESULT_PAN ON Results.QTL (PROTOCOL_APP_NODE_ID);
CREATE INDEX QTL_RESULT_UNDO ON Results.QTL (ROW_ALG_INVOCATION_ID);
CREATE INDEX QTL_RESULT_VRPK ON Results.QTL(VARIANT_RECORD_PRIMARY_KEY);
CREATE INDEX QTL_RESULT_VRPK_NL10P ON Results.QTL(VARIANT_RECORD_PRIMARY_KEY, NEG_LOG10_PVALUE DESC);
CREATE INDEX QTL_RESULT_BIN_INDEX ON Results.QTL USING GIST(BIN_INDEX);
CREATE INDEX QTL_RESULT_PAN_TOP ON Results.QTL(protocol_app_node_id, neg_log10_pvalue desc);
CREATE INDEX QTL_RESULT_PAN_RANK ON Results.QTL(protocol_app_node_id, rank desc);


-- GRANTS

GRANT SELECT ON Results.QTL TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON Results.QTL TO gus_w;

-- SEQUENCES

CREATE SEQUENCE Results.QTL_SQ;
GRANT SELECT ON Results.QTL_SQ TO gus_w;
GRANT SELECT ON Results.QTL_SQ TO gus_r;

-- GUS CORE

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'QTL',
       'Standard', 'QTL_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'Results') d
WHERE 'QTL' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

