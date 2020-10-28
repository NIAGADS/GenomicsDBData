-- table for variants
DROP TABLE IF EXISTS NIAGADS.Variant CASCADE;
DROP SEQUENCE IF EXISTS NIAGADS.Variant_SQ;

CREATE TABLE NIAGADS.Variant  (
       VARIANT_ID			SERIAL NOT NULL, -- to satisfy GUS
       RECORD_PRIMARY_KEY		TEXT NOT NULL PRIMARY KEY,
       METASEQ_ID			TEXT NOT NULL,
       REF_SNP_ID			CHARACTER VARYING(25),

       CHROMOSOME			CHARACTER VARYING(10), -- e.g., 'chr10', for web query optimization and partition hash
       POSITION				BIGINT NOT NULL,
       LOCATION_START			BIGINT, -- for indels/structural variants as LOCATION_START AND POSITION may be different
       LOCATION_END			BIGINT,
       
       BIN_INDEX			LTREE,

       REF_ALLELE			TEXT,
       ALT_ALLELE			TEXT,

       DISPLAY_ALLELE			TEXT,
       SEQUENCE_ALLELE			CHARACTER VARYING(20),
       
       VARIANT_CLASS_ABBREV		CHARACTER VARYING(10)   /* for web query optimization */
       						  CONSTRAINT NV_CHECK_VARIANT_CLASS CHECK (VARIANT_CLASS_ABBREV IN ('SNV', 'MNV', 'DEL', 'INS', 'INDEL', 'SV')),
       
       IS_ADSP_VARIANT			BOOLEAN,
       ANNOTATION			JSONB,
       
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


-- GRANTS

GRANT SELECT ON NIAGADS.Variant TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON NIAGADS.Variant TO gus_w;

-- SEQUENCES

CREATE SEQUENCE NIAGADS.Variant_SQ;
GRANT SELECT ON NIAGADS.Variant_SQ TO gus_w;
GRANT SELECT ON NIAGADS.Variant_SQ TO gus_r;

-- GUS CORE

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'Variant',
       'Standard', 'VARIANT_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'NIAGADS') d
WHERE 'Variant' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

