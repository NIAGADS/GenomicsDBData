-- table for NDD categories / loaded w/LoadGusXml so no referential integrity checks
DROP TABLE IF EXISTS NIAGADS.DataDictionary CASCADE;
DROP SEQUENCE IF EXISTS NIAGADS.DataDictionary_SQ;

CREATE TABLE NIAGADS.DataDictionary  (
       DD_TERM_ID	SERIAL PRIMARY KEY,
       ONTOLOGY_TERM_ID	NUMERIC(12) NOT NULL,
       DISPLAY_VALUE CHARACTER VARYING (200),
       ISA_ONTOLOGY_TERM_ID NUMERIC(12),
       SYNONYMS CHARACTER VARYING(200),
       PHC_CODE CHARACTER VARYING(5),
       ANNOTATION JSONB,
    
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


     CONSTRAINT FK_ONTOLOGY_TERM_ID
       FOREIGN KEY(ONTOLOGY_TERM_ID) 
	  REFERENCES SRes.OntologyTerm(ONTOLOGY_TERM_ID),
     CONSTRAINT FK_ISA_ONTOLOGY_TERM_ID
       FOREIGN KEY(ISA_ONTOLOGY_TERM_ID) 
	  REFERENCES SRes.OntologyTerm(ONTOLOGY_TERM_ID)
     
);

-- INDEXES

CREATE INDEX NDD_INDX01 ON NIAGADS.DataDictionary (ONTOLOGY_TERM_ID);
CREATE INDEX NDD_INDX02 ON NIAGADS.DataDictionary (ISA_ONTOLOGY_TERM_ID);

-- GRANTS

GRANT SELECT ON NIAGADS.DataDictionary TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON NIAGADS.DataDictionary TO gus_w;

-- SEQUENCES

CREATE SEQUENCE NIAGADS.DataDictionary_SQ;
GRANT SELECT ON NIAGADS.DataDictionary_SQ TO gus_w;
GRANT SELECT ON NIAGADS.DataDictionary_SQ TO gus_r;

-- GUS CORE

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'DataDictionary',
       'Standard', 'DD_TERM_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'NIAGADS') d
WHERE 'DataDictionary' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

