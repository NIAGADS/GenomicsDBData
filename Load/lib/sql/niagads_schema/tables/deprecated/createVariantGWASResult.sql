-- table for variant gwas result
DROP TABLE IF EXISTS NIAGADS.VariantGWASResult;
DROP SEQUENCE IF EXISTS NIAGADS.VariantGWASResult_SQ;

CREATE TABLE NIAGADS.VariantGWASResult (
       VARIANT_GWAS_RESULT_ID	     SERIAL PRIMARY KEY,
       PROTOCOL_APP_NODE_ID	     NUMERIC(12) NOT NULL,
       VARIANT_ID		     NUMERIC(12) NOT NULL,
       NEG_LOG10_PVALUE	     	     FLOAT NOT NULL,
       PVALUE_DISPLAY		     CHARACTER VARYING(25) NOT NULL, -- scientific notation
       FREQUENCY		     FLOAT,
       ALLELE			     TEXT,

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

-- INDEXES


CREATE INDEX GWAS_RESULT_IND01 ON NIAGADS.VariantGWASResult USING BRIN(PROTOCOL_APP_NODE_ID);
CREATE INDEX GWAS_RESULT_IND02 ON NIAGADS.VariantGWASResult(VARIANT_ID);
CREATE INDEX GWAS_RESULT_IND03 ON NIAGADS.VariantGWASResult(NEG_LOG10_PVALUE DESC);
CREATE INDEX GWAS_RESULT_IND04 ON NIAGADS.VariantGWASResult(VARIANT_ID) WHERE neg_log10_pvalue >= (-1 * log(5 * power(10, -8)));
CREATE INDEX GWAS_RESULT_IND05 ON NIAGADS.VariantGWASResult(VARIANT_ID) WHERE neg_log10_pvalue >= (-1 * log(1 * power(10, -6)));
CREATE INDEX GWAS_RESULT_IND06 ON NIAGADS.VariantGWASResult(VARIANT_ID) WHERE neg_log10_pvalue >= 3.0;


-- GRANTS

GRANT SELECT ON NIAGADS.VariantGWASResult TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON NIAGADS.VariantGWASResult TO gus_w;

-- SEQUENCES

CREATE SEQUENCE NIAGADS.VariantGWASResult_SQ;
GRANT SELECT ON NIAGADS.VariantGWASResult_SQ TO gus_w;
GRANT SELECT ON NIAGADS.VariantGWASResult_SQ TO gus_r;

-- GUS CORE

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'VariantGWASResult',
       'Standard', 'VARIANT_GWAS_RESULT_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'NIAGADS') d
WHERE 'VariantGWASResult' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

