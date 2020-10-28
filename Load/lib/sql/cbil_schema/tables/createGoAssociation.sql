-- table for Gene-Go-Association
DROP TABLE IF EXISTS CBIL.GoAssociation;
DROP SEQUENCE IF EXISTS CBIL.GoAssociation_SQ;

CREATE TABLE CBIL.GoAssociation (
       GO_ASSOCIATION_ID     SERIAL NOT NULL PRIMARY KEY,
       GENE_ID		     NUMERIC(12) NOT NULL,
       GO_TERM_ID	     NUMERIC(12) NOT NULL,
       EXTERNAL_DATABASE_RELEASE_ID	 NUMERIC(12) NOT NULL,
       EVIDENCE		     JSONB,

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

       FOREIGN KEY (GENE_ID) REFERENCES DoTS.Gene(GENE_ID),
       FOREIGN KEY (GO_TERM_ID) REFERENCES SRes.OntologyTerm(ONTOLOGY_TERM_ID),
       FOREIGN KEY (EXTERNAL_DATABASE_RELEASE_ID) REFERENCES SRes.ExternalDatabaseRelease(EXTERNAL_DATABASE_RELEASE_ID)
);

-- ADDITIONAL CONSTRAINTS



-- INDEXES

CREATE INDEX GOASSOCIATION_INDX01 ON CBIL.GoAssociation(GENE_ID);
CREATE INDEX GOASSOCIATION_INDX02 ON CBIL.GoAssociation(GO_TERM_ID);
CREATE index goassociation_indx03 ON cbil.goassociation(gene_id, go_term_id);
-- GRANTS

GRANT SELECT ON CBIL.GoAssociation TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON CBIL.GoAssociation TO gus_w;

-- SEQUENCES

CREATE SEQUENCE CBIL.GoAssociation_SQ;
GRANT SELECT ON CBIL.GoAssociation_SQ TO gus_w;
GRANT SELECT ON CBIL.GoAssociation_SQ TO gus_r;

-- GUS CORE

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'GoAssociation',
       'Standard', 'GO_ASSOCIATION_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'CBIL') d
WHERE 'GoAssociation' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

