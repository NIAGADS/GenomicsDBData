-- table for variant allele frequencies
DROP TABLE IF EXISTS NIAGADS.VariantAlleleFrequency;
DROP SEQUENCE IF EXISTS NIAGADS.VariantAlleleFrequency_SQ;

CREATE TABLE NIAGADS.VariantAlleleFrequency (
       VARIANT_ALLELE_FREQ_ID		SERIAL NOT NULL PRIMARY KEY,
       -- CHROMOSOME			CHARACTER VARYING(10) NOT NULL, -- may be needed for foreign key to NIAGADS.Variant
       VARIANT_ID		 	NUMERIC(12) NOT NULL,
       PROTOCOL_APP_NODE_ID		NUMERIC(10) NOT NULL,
       ALLELE				CHARACTER VARYING(250) NOT NULL,
       FREQUENCY		FLOAT NOT NULL,		
       POPULATION_ID		NUMERIC(12) NOT NULL,
       INFO			JSONB,

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
       ROW_ALG_INVOCATION_ID	 NUMERIC(12),
       -- FOREIGN KEY (NA_FEATURE_ID) REFERENCES DoTS.NAFeatureImp(NA_FEATURE_ID),
       FOREIGN KEY (PROTOCOL_APP_NODE_ID) REFERENCES Study.ProtocolAppNode(PROTOCOL_APP_NODE_ID)

);

CREATE INDEX VARIANT_ALLELE_FREQ_IND01 ON NIAGADS.VariantAlleleFrequency (VARIANT_PRIMARY_KEY);
CREATE INDEX VARIANT_ALLELE_FREQ_IND02 ON NIAGADS.VariantAlleleFrequency (NA_FEATURE_ID);
CREATE INDEX VARIANT_ALLELE_FREQ_IND03 ON NIAGADS.VariantAlleleFrequency (PROTOCOL_APP_NODE_ID, FREQUENCY);

GRANT SELECT ON NIAGADS.VariantAlleleFrequency TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON NIAGADS.VariantAlleleFrequency TO gus_w;

CREATE SEQUENCE NIAGADS.VariantAlleleFrequency_SQ;
GRANT SELECT ON NIAGADS.VariantAlleleFrequency_SQ TO gus_w;
GRANT SELECT ON NIAGADS.VariantAlleleFrequency_SQ TO gus_r;

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'VariantAlleleFrequency',
       'Standard', 'VARIANT_ALLELE_FREQ_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'NIAGADS') d
WHERE 'VariantAlleleFrequency' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

