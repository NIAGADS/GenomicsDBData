-- table for NDD categories / loaded w/LoadGusXml so no referential integrity checks
DROP TABLE IF EXISTS NIAGADS.DataDictionary CASCADE;
DROP SEQUENCE IF EXISTS NIAGADS.DataDictionary_SQ;

CREATE TABLE NIAGADS.DataDictionary  (
       DD_TERM_ID	SERIAL PRIMARY KEY,
       ONTOLOGY_TERM_ID	CHARACTER VARYING (50) NOT NULL,
       TERM            CHARACTER VARYING (200) NOT NULL,
       UNITS CHARACTER VARYING(25),
       DISPLAY_VALUE CHARACTER VARYING (200),
       IS_A CHARACTER VARYING (50) NOT NULL,
       is_metadata_field BOOLEAN,
       metadata_field_label	CHARACTER VARYING (50),
       metadata_field_value_type	CHARACTER VARYING (50),
       metadata_field_instructions	CHARACTER VARYING (4000),
       ols_search_api_call	CHARACTER VARYING (4000),
       metadata_tag	CHARACTER VARYING (50),
       metadata_sheet	CHARACTER VARYING (50),
       definition CHARACTER VARYING (4000),

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

CREATE INDEX NDD_INDX01 ON NIAGADS.DataDictionary (ONTOLOGY_TERM_ID);
CREATE INDEX NDD_INDX02 ON NIAGADS.DataDictionary (TERM);
CREATE INDEX NDD_INDX03 ON NIAGADS.DataDictionary (METADATA_TAG);
CREATE INDEX NDD_INDX04 ON NIAGADS.DataDictionary (METADATA_SHEET);

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

