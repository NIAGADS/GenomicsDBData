-- table for variant ld result
DROP TABLE IF EXISTS Results.Motif;
DROP SEQUENCE IF EXISTS Results.Motif_SQ;

CREATE UNLOGGED TABLE Results.Motif (
       MOTIF_ID SERIAL NOT NULL,
       EXTERNAL_DATABASE_RELEASE_ID  NUMERIC(12) NOT NULL,
       CHROMOSOME		     CHARACTER VARYING(10) NOT NULL,
       LOCATION_START		     INTEGER NOT NULL,
       LOCATION_END		     INTEGER NOT NULL,
       BIN_INDEX		     LTREE NOT NULL,
       MOTIF_SOURCE_ID			     CHARACTER VARYING(50) NOT NULL,
       MATRIX_ID		     CHARACTER VARYING(50) NOT NULL,
       FEATURE_TYPE			     CHARACTER VARYING(50),
       SCORE			     FLOAT,
       ANNOTATION		     JSONB,

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
) PARTITION BY LIST (CHROMOSOME);

-- CREATE PARTITIONS

CREATE OR REPLACE FUNCTION "public"."create_ld_partitions" ()  RETURNS integer
  VOLATILE
  AS $body$
DECLARE
      partition TEXT;
      chr TEXT;
    BEGIN

      FOR chr IN
        SELECT UNNEST(string_to_array('chr1 chr2 chr3 chr4 chr5 chr6 chr7 chr8 chr9 chr10 chr11 chr12 chr13 chr14 chr15 chr16 chr17 chr18 chr19 chr20 chr21 chr22 chrX chrY chrM', ' '))
      LOOP
        partition := 'Results.Motif' || '_' || chr::text;
        IF NOT EXISTS(SELECT relname FROM pg_class WHERE relname=partition) THEN
           EXECUTE 'CREATE TABLE ' || partition || ' PARTITION OF Results.Motif FOR VALUES IN (''' || chr || ''')';
           RAISE NOTICE 'A partition has been created %',partition;
         END IF;
      END LOOP;
      RETURN NULL;
    END;
$body$ LANGUAGE plpgsql;

SELECT create_ld_partitions();

-- TRIGGERS

CREATE TRIGGER set_bin_trigger 
AFTER INSERT OR UPDATE ON Results.Motif 
FOR EACH ROW 
  EXECUTE PROCEDURE set_row_bin_index();

-- INDEXES

CREATE INDEX MOTIF_MATRIX ON Results.Motif(motif_source_id, matrix_id);
/* CREATE INDEX MOTIF_BIN_INDEX ON Results.Motif USING GIST(BIN_INDEX);
*/

-- GRANTS

GRANT SELECT ON Results.Motif TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON Results.Motif TO gus_w;

-- SEQUENCES

CREATE SEQUENCE Results.Motif_SQ;
GRANT SELECT ON Results.Motif_SQ TO gus_w;
GRANT SELECT ON Results.Motif_SQ TO gus_r;

-- GUS CORE

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'Motif',
       'Standard', 'MOTIF_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'Results') d
WHERE 'Motif' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

