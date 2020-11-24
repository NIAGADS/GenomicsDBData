-- table for merged variants
DROP TABLE IF EXISTS NIAGADS.Population;
DROP SEQUENCE IF EXISTS NIAGADS.Population_SQ;

CREATE TABLE NIAGADS.Population  (
       POPULATION_ID	SERIAL PRIMARY KEY,
       ONTOLOGY_TERM_ID	NUMERIC(12),
       ABBREVIATION	CHARACTER VARYING (10) NOT NULL,
       DISPLAY_VALUE	CHARACTER VARYING (50) NOT NULL,
       DATASOURCE	CHARACTER VARYING (50) NOT NULL,
       SOURCE_ID	CHARACTER VARYING (50) NOT NULL,
       DESCRIPTION	CHARACTER VARYING (300),
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
       CONSTRAINT POP_ONT_TERM FOREIGN KEY (ontology_term_id) REFERENCES SRes.OntologyTerm(ontology_term_id)
);

-- INDEXES

CREATE INDEX POPULATION_IND01 ON NIAGADS.Population (source_id);

-- GRANTS

GRANT SELECT ON NIAGADS.Population TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON NIAGADS.Population TO gus_w;

-- SEQUENCES

CREATE SEQUENCE NIAGADS.Population_SQ;
GRANT SELECT ON NIAGADS.Population_SQ TO gus_w;
GRANT SELECT ON NIAGADS.Population_SQ TO gus_r;

-- GUS CORE

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'Population',
       'Standard', 'POPULATION_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'NIAGADS') d
WHERE 'Population' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

