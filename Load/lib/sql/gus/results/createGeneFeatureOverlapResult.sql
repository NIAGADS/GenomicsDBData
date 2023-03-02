-- table for variant ld result
DROP TABLE IF EXISTS Results.GeneFeatureOverlap;
DROP SEQUENCE IF EXISTS Results.GeneFeatureOverlap_SQ;

CREATE UNLOGGED TABLE Results.GeneFeatureOverlap (
       GENE_FEATURE_OVERLAP_ID	 SERIAL PRIMARY KEY,
       EXTERNAL_DATABASE_RELEASE_ID NUMERIC(12) NOT NULL,
       FILER_TRACK_ID	    CHARACTER VARYING(25) NOT NULL,
       GENE_ID              NUMERIC(12) NOT NULL,
       CHROMOSOME          CHARACTER VARYING(10) NOT NULL,
       LOCATION_START      INTEGER NOT NULL,
       LOCATION_END        INTEGER NOT NULL,
       HIT_STATS         JSONB,
            
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
       ROW_ALG_INVOCATION_ID	 NUMERIC(12),

        CONSTRAINT FK_GENE
      FOREIGN KEY(gene_id) 
	  REFERENCES DoTS.Gene(gene_id)
);

-- INDEXES

CREATE INDEX GFO_GENE ON Results.GeneFeatureOverlap(GENE_ID);
CREATE INDEX GFO_TRACK ON Results.GeneFeatureOverlap(FILER_TRACK_ID);
CREATE INDEX GFO_DATA_SOURCE ON Results.GeneFeatureOverlap(DATA_SOURCE);

-- GRANTS

GRANT SELECT ON Results.GeneFeatureOverlap TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON Results.GeneFeatureOverlap TO gus_w;

-- SEQUENCES

CREATE SEQUENCE Results.GeneFeatureOverlap_SQ;
GRANT SELECT ON Results.GeneFeatureOverlap_SQ TO gus_w;
GRANT SELECT ON Results.GeneFeatureOverlap_SQ TO gus_r;

-- TRIGGERS


-- GUS CORE

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'GeneFeatureOverlap',
       'Standard', 'GENE_FEATURE_OVERLAP_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'Results') d
WHERE 'GeneFeatureOverlap' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

