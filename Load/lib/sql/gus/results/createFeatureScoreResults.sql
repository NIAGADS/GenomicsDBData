-- table for variant ld result
DROP TABLE IF EXISTS Results.FeatureScore;
DROP SEQUENCE IF EXISTS Results.FeatureScore_SQ;

CREATE UNLOGGED TABLE Results.FeatureScore (
       FEATURE_SCORE_ID	     SERIAL PRIMARY KEY,
       PROTOCOL_APP_NODE_ID	     NUMERIC(12) NOT NULL,
       BIN_INDEX		     LTREE NOT NULL,
       FEATURE_NAME		     CHARACTER VARYING(100),
       CHROMOSOME		     CHARACTER VARYING(10), -- e.g., 'chr10', for web query optimization and partition hash
       LOCATION_START		     INTEGER NOT NULL,
       LOCATION_END		     INTEGER NOT NULL,
       STRAND	    		     CHARACTER VARYING(1),
       SCORE			     NUMERIC,
       POSITION_CM		     FLOAT,
       
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

CREATE INDEX FS_DATASET ON Results.FeatureScore USING BRIN(PROTOCOL_APP_NODE_ID);
CREATE INDEX FS_BIN_INDEX ON Results.FeatureScore USING GIST(BIN_INDEX);

-- GRANTS

GRANT SELECT ON Results.FeatureScore TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON Results.FeatureScore TO gus_w;

-- SEQUENCES

CREATE SEQUENCE Results.FeatureScore_SQ;
GRANT SELECT ON Results.FeatureScore_SQ TO gus_w;
GRANT SELECT ON Results.FeatureScore_SQ TO gus_r;

-- TRIGGERS

CREATE TRIGGER results_feature_score_bin_trigger BEFORE INSERT OR UPDATE ON Results.FeatureScore
       FOR EACH ROW EXECUTE PROCEDURE set_row_bin_index();

-- GUS CORE

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'FeatureScore',
       'Standard', 'FEATURE_SCORE_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'Results') d
WHERE 'FeatureScore' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

