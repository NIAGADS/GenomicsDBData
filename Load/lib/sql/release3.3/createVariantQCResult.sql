-- table for variant effect predictions
DROP TABLE IF EXISTS NIAGADS.VariantQC;
DROP SEQUENCE IF EXISTS NIAGADS.VariantQC_SQ;

CREATE TABLE NIAGADS.VariantQC (
       VARIANTQC_ID	SERIAL NOT NULL PRIMARY KEY,
       NA_FEATURE_ID		 	NUMERIC(12) NOT NULL,
       PROTOCOL_APP_NODE_ID		NUMERIC(10) NOT NULL,

       VARIANT_PRIMARY_KEY		CHARACTER VARYING(500) NOT NULL,

       PLATFORM				CHARACTER VARYING(25) NOT NULL, -- BROAD, BAYLOR, CONSENSUS
       FILTER				CHARACTER VARYING(100),
       QUALITY_SCORE			FLOAT,
       FLAGS				CHARACTER VARYING(500),
       CAPTURE				BOOLEAN,
       BI_PASS				BOOLEAN,
       LOW_MAPPING_SCORE		BOOLEAN,
       GENOTYPE_00			JSONB, -- incls. BaPass00, BaFail00, genoCount00 (consensus)
       GENOTYPE_01			JSONB,
       GENOTYPE_11			JSONB,
       GENOTYPE_MISSING			NUMERIC(5), -- = genoCountMissing (consensus)
       GENOTYPE_MULTIALLELIC		NUMERIC(5),
       MONOMORPHIC			BOOLEAN,
       CALL_RATE			FLOAT,     
       CALL_BAD				BOOLEAN,
       MEAN_DEPTH			FLOAT,
       HIGH_DEPTH			FLOAT,
       FILTERED_OUT			BOOLEAN,
       MENDELIAN_INCONSISTENCIES	CHARACTER VARYING(500), -- no idea what goes in this field; may change
       MAF				FLOAT,
       GENOTYPE_COUNTS			JSONB, -- counts per catgegory of consensus codes
       HWE_PVALUE			FLOAT,
       HWE_BIN				NUMERIC(1), -- (“0” MAF>0.01; “1” MAF<0.01)
       HWE_EXC				BOOLEAN,
       HET_ZSCORE			FLOAT,
       HET_BIN				NUMERIC(1),
       HET_EXC				BOOLEAN, --“HetExc” (“0” if  |z)| ≤ 5 SD(z,MAF); “1” if |z|  > 5 SD(z,MAF) )
       INFO				JSONB,

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
       --FOREIGN KEY (NA_FEATURE_ID) REFERENCES DoTS.NAFeatureImp (NA_FEATURE_ID),
       FOREIGN KEY (PROTOCOL_APP_NODE_ID) REFERENCES Study.ProtocolAppNode (PROTOCOL_APP_NODE_ID)

    
);

CREATE INDEX VARIANTQC_IND01 ON NIAGADS.VARIANTQC (VARIANT_PRIMARY_KEY);
CREATE INDEX VARIANTQC_IND02 ON NIAGADS.VARIANTQC (NA_FEATURE_ID);

GRANT SELECT ON NIAGADS.VariantQC TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON NIAGADS.VariantQC TO gus_w;

CREATE SEQUENCE NIAGADS.VariantQC_SQ;
GRANT SELECT ON NIAGADS.VariantQC_SQ TO gus_w;
GRANT SELECT ON NIAGADS.VariantQC_SQ TO gus_r;

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'VariantQC',
       'Standard', 'VARIANTQC_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'NIAGADS') d
WHERE 'VariantQC' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

