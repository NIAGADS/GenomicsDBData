-- table for  track collections
DROP TABLE IF EXISTS NIAGADS.Collection;
DROP SEQUENCE IF EXISTS NIAGADS.Collection_SQ;


CREATE TABLE NIAGADS.Collection  (
       COLLECTION_ID	SERIAL PRIMARY KEY,
       NAME             CHARACTER VARYING(100) NOT NULL,
       DESCRIPTION      TEXT NOT NULL,
       
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

-- POC data

INSERT INTO NIAGADS.COLLECTION (name, description)
SELECT 
'xQTL-Project',
'quantitative trait loci (QTL) are genetic regions that influence phenotypic variation of a molecular (transcriptomic, proteomic, lipidomic among others) trait. The xQTL project is a collaborative effort across the FunGen-AD, the Accelerating Medicines Partnership Alzheimer’s Disease (AMP AD), the NIH Center for Alzheimer’s and Related Dementias (CARD), and the ADSP.'
;

INSERT INTO NIAGADS.COLLECTION (name, description)
SELECT 
'AD-GWAS-sum-stats',
'GWAS summary statistics datasets with a focus on Alzheimer''s disease, primarily from the NIAGADS repository'
;

INSERT INTO NIAGADS.COLLECTION (name, description)
SELECT 
'ADRD-GWAS-sum-stats',
'GWAS summary statisitics on AD related dementias, primarily from the NIAGADS repository'
;

-- INDEXES

GRANT SELECT ON NIAGADS.Collection TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON NIAGADS.Collection TO gus_w;

-- SEQUENCES

CREATE SEQUENCE NIAGADS.Collection_SQ;
GRANT SELECT ON NIAGADS.Collection_SQ TO gus_w;
GRANT SELECT ON NIAGADS.Collection_SQ TO gus_r;

-- GUS CORE

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'Collection',
       'Standard', 'COLLECTION_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'NIAGADS') d
WHERE 'Collection' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

