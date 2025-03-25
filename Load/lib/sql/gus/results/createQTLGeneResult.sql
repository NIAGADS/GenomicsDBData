-- table for variant gwas result
DROP TABLE IF EXISTS Results.QTLGene;
DROP SEQUENCE IF EXISTS Results.QTLGene_SQ;

CREATE TABLE Results.QTLGene (
        QTL_GENE_ID	     	 SERIAL PRIMARY KEY,
        TRACK_ID	     CHARACTER VARYING(50) NOT NULL,
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
        NUM_QTLS_TARGETING_GENE INTEGER NOT NULL,

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

--ALTER TABLE Results.QTLGene ADD CONSTRAINT CONST_QTL_TARGET_ID FOREIGN KEY (target_id) REFERENCES DOTS.Gene (source_id);

-- INDEXES

CREATE INDEX QG_RESULT_TRACK ON Results.QTLGene (TRACK_ID);
CREATE INDEX QG_RESULT_TRACK_TOP ON Results.QTLGene(TRACK_ID, NEG_LOG10_PVALUE DESC);
CREATE INDEX QG_RESULT_TRACK_RANK ON Results.QTLGene(TRACK_ID, RANK DESC);

CREATE INDEX QG_RESULT_BIN_INDEX ON Results.QTLGene USING GIST(BIN_INDEX);
CREATE INDEX QG_RESULT_UNDO ON Results.QTLGene (ROW_ALG_INVOCATION_ID);

CREATE INDEX QG_RESULT_VRPK ON Results.QTLGene(VARIANT_RECORD_PRIMARY_KEY);
CREATE INDEX QG_RESULT_GENE ON Results.QTLGene(TARGET_ENSEMBL_ID);

-- GRANTS

GRANT SELECT ON Results.QTLGene TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON Results.QTLGene TO gus_w;

-- SEQUENCES

CREATE SEQUENCE Results.QTLGene_SQ;
GRANT SELECT ON Results.QTLGene_SQ TO gus_w;
GRANT SELECT ON Results.QTLGene_SQ TO gus_r;

-- GUS CORE

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'QTLGene',
       'Standard', 'QTL_GENE_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'Results') d
WHERE 'QTLGene' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

