DROP TABLE IF EXISTS NIAGADS.NHGRIOntologySynonym;
DROP SEQUENCE IF EXISTS NIAGADS.NHGRIOntologySynonym_SQ;

CREATE TABLE NIAGADS.NHGRIOntologySynonym (
       nhgri_ontology_synonym_id SERIAL NOT NULL PRIMARY KEY,
       nhgri_term CHARACTER VARYING(500) NOT NULL,
       nhgri_term_id NUMERIC(10),
       efo_term	CHARACTER VARYING(4000),
       efo_source_id CHARACTER VARYING(100) NOT NULL,

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

CREATE INDEX NCOS_IND01 ON NIAGADS.NHGRIOntologySynonym(NHGRI_TERM, EFO_SOURCE_ID);
CREATE INDEX NCOS_IND02 ON NIAGADS.NHGRIOntologySynonym(EFO_SOURCE_ID, NHGRI_TERM);


GRANT SELECT ON NIAGADS.NHGRIOntologySynonym TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON NIAGADS.NHGRIOntologySynonym TO gus_w;

CREATE SEQUENCE NIAGADS.NHGRIOntologySynonym_SQ;
GRANT SELECT ON NIAGADS.NHGRIOntologySynonym_SQ TO gus_w;
GRANT SELECT ON NIAGADS.NHGRIOntologySynonym_SQ TO gus_r;

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'NHGRIOntologySynonym',
       'Standard', 'NHGRI_ONTOLOGY_SYNONYM_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'NIAGADS') d
WHERE 'NHGRIOntologySynonym' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);



