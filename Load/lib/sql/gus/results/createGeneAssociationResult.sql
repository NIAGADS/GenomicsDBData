-- table for Gene SKATO results
-- https://cran.r-project.org/web/packages/seqMeta/vignettes/seqMeta.pdf

DROP TABLE IF EXISTS NIAGADS.GeneAssociation;
DROP SEQUENCE IF EXISTS NIAGADS.GeneAssociation_SQ;

CREATE TABLE NIAGADS.GeneAssociation (
       GENE_ASSOCIATION_ID	  SERIAL PRIMARY KEY,
       GENE_ID				 NUMERIC(10) NOT NULL,
       PROTOCOL_APP_NODE_ID		 NUMERIC(12) NOT NULL,
       P_VALUE				 FLOAT NOT NULL,
       MIN_P_VALUE			 FLOAT, -- minimum p-value across all tests (SKAT-O)
       RHO			 	 FLOAT, -- specifies which test yields PMIN
       CUMULATIVE_MAF			 FLOAT, -- MAF of a variant across all variants in the gene
       CUMULATIVE_MAC			 FLOAT, -- estimate cumulative minor allele count (ntotal * 2 * cmaf)
       NUM_SNPS				 INTEGER, --count of variants included in the test
       SCORES				 JSONB, -- additional scores or tallies; may vary by analysis
       CAVEAT				 JSONB,
       COMMENT				 JSONB,
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
       FOREIGN KEY(GENE_ID) REFERENCES DoTS.Gene(GENE_ID),
       FOREIGN KEY(PROTOCOL_APP_NODE_ID) REFERENCES Study.ProtocolAppNode(PROTOCOL_APP_NODE_ID)
);

CREATE INDEX GENE_TRAITASSOCIATION_IND01 ON NIAGADS.GeneAssociation (GENE_ID);
CREATE INDEX GENE_TRAITASSOCIATION_IND02 ON NIAGADS.GeneAssociation (PROTOCOL_APP_NODE_ID);
CREATE INDEX GENE_TRAITASSOCIATION_IND03 ON NIAGADS.GeneAssociation (P_VALUE);
CREATE INDEX GENE_TRAITASSOCIATION_IND04 ON NIAGADS.GeneAssociation (MIN_P_VALUE);

CREATE SEQUENCE NIAGADS.GeneAssociation_SQ;

GRANT SELECT ON NIAGADS.GeneAssociation TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON NIAGADS.GeneAssociation TO gus_w;

GRANT SELECT ON NIAGADS.GeneAssociation_SQ TO gus_w;
GRANT SELECT ON NIAGADS.GeneAssociation_SQ TO gus_r;

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'GeneAssociation',
       'Standard', 'GENE_ASSOCIATION_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'NIAGADS') d
WHERE 'GeneAssociation' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

