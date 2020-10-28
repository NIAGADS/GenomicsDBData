/* for functional enrichment tool */
/* depends on NIAGADS.GOAssociation_TC; see createTcGOAssociationTuning_MVs.sql) */

DROP MATERIALIZED VIEW IF EXISTS NIAGADS.GeneOntologyTotals;

CREATE MATERIALIZED VIEW NIAGADS.GeneOntologyTotals AS (
SELECT COUNT(DISTINCT source_id) AS num_annotated_genes
, ontology 
FROM NIAGADS.GOAssociation_TC
GROUP BY ontology
);

GRANT SELECT ON NIAGADS.GeneOntologyTotals TO genomicsdb;
