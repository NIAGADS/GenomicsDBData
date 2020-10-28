-- table to link questions to resources
DROP TABLE IF EXISTS CBIL.DbRefLink;
DROP SEQUENCE IF EXISTS CBIL.DbRefLink_SQ;

CREATE TABLE CBIL.DbRefLink (
DBREF_LINK_ID	SERIAL NOT NULL PRIMARY KEY,
DBREF_ID		CHARACTER VARYING(50) NOT NULL,
RESOURCE_TYPE		CHARACTER VARYING(100) NOT NULL,
RESOURCE_FULL_NAME		CHARACTER VARYING(250) NOT NULL,
RESOURCE_ABBREV		CHARACTER VARYING(50) NOT NULL,
URL		CHARACTER VARYING(1000) NOT NULL,	


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


GRANT SELECT ON CBIL.DbRefLink TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON CBIL.DbRefLink TO gus_w;
GRANT INSERT, SELECT, UPDATE, DELETE ON CBIL.DbRefLink TO comm_wdk_w;

CREATE SEQUENCE CBIL.DbRefLink_SQ;
GRANT SELECT ON CBIL.DbRefLink_SQ TO gus_w;
GRANT SELECT ON CBIL.DbRefLink_SQ TO gus_r;

INSERT INTO Core.TableInfo
(table_id, name, table_type, primary_key_column, database_id, is_versioned,
is_view, view_on_table_id, superclass_table_id, is_updatable,
modification_date, user_read, user_write, group_read, group_write,
other_read, other_write, row_user_id, row_group_id, row_project_id,
row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'DbRefLink',
'Standard', 'DBREF_LINK_ID',
d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
p.project_id, 0
FROM
(SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
(SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'CBIL') d
WHERE 'DbRefLink' NOT IN (SELECT NAME FROM Core.TableInfo
WHERE database_id = d.database_id);
