-- table for variant effect predictions
DROP TABLE IF EXISTS NIAGADS.PredictedVariantEffect;
DROP SEQUENCE IF EXISTS NIAGADS.PredictedVariantEffect_SQ;

CREATE TABLE NIAGADS.PredictedVariantEffect (
       PREDICTED_VARIANT_EFFECT_ID	SERIAL NOT NULL PRIMARY KEY,
       NA_FEATURE_ID		 	NUMERIC(12) NOT NULL,
       PROTOCOL_APP_NODE_ID		NUMERIC(10) NOT NULL,

       VARIANT_PRIMARY_KEY		CHARACTER VARYING(500) NOT NULL,

       ALLELE				CHARACTER VARYING(500) NOT NULL,

       EFFECT_IMPACT		  	CHARACTER VARYING(50),
       EFFECT_RANK		  	NUMERIC(3),
       IS_MOST_SEVERE_CONSEQUENCE	BOOLEAN,
       SEQUENCE_ONTOLOGY_ID	  	NUMERIC(10),
       CONSEQUENCE			CHARACTER VARYING(500),

       GENE_SOURCE_ID		        CHARACTER VARYING(100),
       GENE_FEATURE_ID			NUMERIC(10),

       ASSOCIATED_GENE_SOURCE_ID	CHARACTER VARYING(100),
       ASSOCIATED_GENE_FEATURE_ID	NUMERIC(10),

       GENE_ASSOCIATION			CHARACTER VARYING(20),

       FEATURE_TYPE			CHARACTER VARYING(500),       
       FEATURE				CHARACTER VARYING(500),
       FEATURE_ID			NUMERIC(10),
       
       INTRON			  CHARACTER VARYING(20),
       EXON			  CHARACTER VARYING(20),
       DISTANCE			  NUMERIC(12),
       CDNA_POSITION		  CHARACTER VARYING(100),
       CDS_POSITION		  CHARACTER VARYING(100),
       PROTEIN_POSITION		  CHARACTER VARYING(100),
       AMINO_ACID_CHANGE	  CHARACTER VARYING(200),
       CODON_CHANGE		  CHARACTER VARYING(500),
       ANNOTATION			  JSONB,

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
       -- FOREIGN KEY (FEATURE_ID) REFERENCES DoTS.NAFeatureImp(NA_FEATURE_ID)
       FOREIGN KEY (PROTOCOL_APP_NODE_ID) REFERENCES Study.ProtocolAppNode(PROTOCOL_APP_NODE_ID),
       FOREIGN KEY (SEQUENCE_ONTOLOGY_ID) REFERENCES SRes.OntologyTerm (ONTOLOGY_TERM_ID)
);

CREATE INDEX PREDICTED_VARIANT_EFFECT_IND01 ON NIAGADS.PredictedVariantEffect (VARIANT_PRIMARY_KEY);
CREATE INDEX PREDICTED_VARIANT_EFFECT_IND02 ON NIAGADS.PredictedVariantEffect (NA_FEATURE_ID);
CREATE INDEX PREDICTED_VARIANT_EFFECT_IND03 ON NIAGADS.PredictedVariantEffect (GENE_SOURCE_ID);

GRANT SELECT ON NIAGADS.PredictedVariantEffect TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON NIAGADS.PredictedVariantEffect TO gus_w;

CREATE SEQUENCE NIAGADS.PredictedVariantEffect_SQ;
GRANT SELECT ON NIAGADS.PredictedVariantEffect_SQ TO gus_w;
GRANT SELECT ON NIAGADS.PredictedVariantEffect_SQ TO gus_r;

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'PredictedVariantEffect',
       'Standard', 'PREDICTED_VARIANT_EFFECT_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'NIAGADS') d
WHERE 'PredictedVariantEffect' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

