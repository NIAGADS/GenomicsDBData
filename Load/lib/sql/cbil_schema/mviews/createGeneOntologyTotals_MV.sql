/* for functional enrichment tool */
/* depends on CBIL.GOAssociation; see createGOAssociationTuning_MVs.sql) */

DROP MATERIALIZED VIEW IF EXISTS CBIL.GeneOntologyTotals;

CREATE MATERIALIZED VIEW CBIL.GeneOntologyTotals AS (
SELECT COUNT(DISTINCT source_id) AS num_annotated_genes
, ontology_abbrev
, ontology
, taxon_id
, organism
FROM CBIL.GOAssociation
GROUP BY ontology_abbrev, ontology, taxon_id, organism
);

GRANT SELECT ON CBIL.GeneOntologyTotals TO comm_wdk_w;
