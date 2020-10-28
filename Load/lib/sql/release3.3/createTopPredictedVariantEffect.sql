-- table for most-severe variant effect predictions
DROP TABLE NIAGADS.TopPredictedVariantEffect;

CREATE TABLE NIAGADS.TopPredictedVariantEffect (
       TOP_VARIANT_EFFECT_ID		 SERIAL PRIMARY KEY,
       NA_FEATURE_ID		 NUMERIC(12) NOT NULL,
       PROTOCOL_APP_NODE_ID		 NUMERIC(10) NOT NULL,
       VARIANT_ID			 CHARACTER VARYING(1000) NOT NULL,
       GENE_SOURCE_ID		         CHARACTER VARYING(100),
       ANNOTATION 			 JSONB,
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
       FOREIGN KEY (PROTOCOL_APP_NODE_ID) REFERENCES Study.ProtocolAppNode(PROTOCOL_APP_NODE_ID)
      -- FOREIGN KEY (NA_FEATURE_ID) REFERENCES DoTS.NAFeatureImp(NA_FEATURE_ID),
       -- FOREIGN KEY (GENE_SOURCE_ID) REFERENCES DoTS.GeneFeature (SOURCE_ID) --,
);

CREATE INDEX TOP_PREDICTED_VARIANT_EFFECT_IND01 ON NIAGADS.TopPredictedVariantEffect (VARIANT_ID, NA_FEATURE_ID);
CREATE INDEX TOP_PREDICTED_VARIANT_EFFECT_IND02 ON NIAGADS.TopPredictedVariantEffect (NA_FEATURE_ID);
CREATE INDEX TOP_PREDICTED_VARIANT_EFFECT_IND03 ON NIAGADS.TopPredictedVariantEffect (PROTOCOL_APP_NODE_ID, VARIANT_ID);
CREATE INDEX TOP_PREDICTED_VARIANT_EFFECT_GIND01 ON NIAGADS.TopPredictedVariantEffect (ANNOTATION);

GRANT SELECT ON NIAGADS.TopPredictedVariantEffect TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON NIAGADS.TopPredictedVariantEffect TO gus_w;



INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'TopPredictedVariantEffect',
       'Standard', 'TOP_VARIANT_EFFECT_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'NIAGADS') d
WHERE 'TopPredictedVariantEffect' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

