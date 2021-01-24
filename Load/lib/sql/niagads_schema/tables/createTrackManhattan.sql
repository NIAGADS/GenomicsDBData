-- table for variant gwas result
DROP TABLE IF EXISTS NIAGADS.TrackManhattan;
DROP SEQUENCE IF EXISTS NIAGADS.TrackManhattan_SQ;

CREATE TABLE NIAGADS.TrackManhattan (
       TRACK_MANHATTAN_ID	     SERIAL PRIMARY KEY,
       TRACK			     CHARACTER VARYING(100) NOT NULL,
       MANHATTAN_PLOT		     BYTEA,
       CIRCULAR_MANHATTAN_PLOT	     BYTEA,
       ANNOTATED_MANHATTAN_PLOT	     BYTEA,

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

CREATE INDEX TMN_INDO01 ON NIAGADS.TrackManhattan(TRACK);

-- GRANTS

GRANT SELECT ON NIAGADS.TrackManhattan TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON NIAGADS.TrackManhattan TO gus_w;

-- SEQUENCES

CREATE SEQUENCE NIAGADS.TrackManhattan_SQ;
GRANT SELECT ON NIAGADS.TrackManhattan_SQ TO gus_w;
GRANT SELECT ON NIAGADS.TrackManhattan_SQ TO gus_r;

-- GUS CORE

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'TrackManhattan',
       'Standard', 'TRACK_MANHATTAN_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'NIAGADS') d
WHERE 'TrackManhattan' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

