-- table to link questions to resources
DROP TABLE IF EXISTS NIAGADS.QuestionDetails;
DROP SEQUENCE IF EXISTS NIAGADS.QuestionDetails_SQ;

CREATE TABLE NIAGADS.QuestionDetails (
       QUESTION_DETAIL_ID		 NUMERIC(10) NOT NULL PRIMARY KEY,
       QUESTION_FULL_NAME	CHARACTER VARYING (100) NOT NULL,
       DISPLAY_NAME		CHARACTER VARYING (100),
       FULL_DISPLAY_NAME	CHARACTER VARYING (200),
       DESCRIPTION		CHARACTER VARYING (500),
       RECORD_TYPE 		CHARACTER VARYING (100),
       SEARCH_GRID_CATEGORY	CHARACTER VARYING (100),
       SELECT_OPTION_DISPLAY	CHARACTER VARYING (100),
       SHORT_DISPLAY_NAME	CHARACTER VARYING (50),
       PARAMETER_DESCRIPTION	CHARACTER VARYING (500),
       SUMMARY			CHARACTER VARYING (500),

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

ALTER TABLE NIAGADS.QuestionDetails ADD CONSTRAINT QD_UNIQUE_CONSTRAINT UNIQUE (QUESTION_FULL_NAME);

GRANT SELECT ON NIAGADS.QuestionDetails TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON NIAGADS.QuestionDetails TO gus_w;

CREATE SEQUENCE NIAGADS.QuestionDetails_SQ;
GRANT SELECT ON NIAGADS.QuestionDetails_SQ TO gus_w;
GRANT SELECT ON NIAGADS.QuestionDetails_SQ TO gus_r;

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'QuestionDetails',
       'Standard', 'QUESTION_DETAIL_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'NIAGADS') d
WHERE 'QuestionDetails' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

