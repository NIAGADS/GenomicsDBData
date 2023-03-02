-- table for gnomAD gene constraints (http://gnomad-sg.org/help/constraint)
DROP TABLE IF EXISTS Results.GeneConstraint;
DROP SEQUENCE IF EXISTS Results.GeneConstraint_SQ;

CREATE TABLE Results.GeneConstraint (
       GENE_CONSTRAINT_ID	 SERIAL PRIMARY KEY,
       GENE_ID      NUMERIC(12) NOT NULL,
       TRANSCRIPT_ID     NUMERIC(12) NOT NULL,
       SCORES JSONB NOT NULL,
            
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
      FOREIGN KEY(GENE_ID) 
	  REFERENCES DoTS.Gene(GENE_ID),
     CONSTRAINT FK_TRANSCRIPT
          FOREIGN KEY(TRANSCRIPT_ID)
          REFERENCES DoTS.NAFeatureImp(NA_FEATURE_ID)
);

-- INDEXES

CREATE INDEX GCR_INDEX01 ON Results.GeneConstraint(GENE_ID);
CREATE INDEX GCR_INDEX02 ON Results.GeneConstraint(TRANSCRIPT_ID);


-- GRANTS

GRANT SELECT ON Results.GeneConstraint TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON Results.GeneConstraint TO gus_w;

-- SEQUENCES

CREATE SEQUENCE Results.GeneConstraint_SQ;
GRANT SELECT ON Results.GeneConstraint_SQ TO gus_w;
GRANT SELECT ON Results.GeneConstraint_SQ TO gus_r;

-- TRIGGERS


-- GUS CORE

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'GeneConstraint',
       'Standard', 'GENE_CONSTRAINT_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'Results') d
WHERE 'GeneConstraint' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

