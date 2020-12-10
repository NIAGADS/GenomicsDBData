DROP MATERIALIZED VIEW IF EXISTS NIAGADS.GeneAssociationCorrection;

CREATE MATERIALIZED VIEW NIAGADS.GeneAssociationCorrection AS (
SELECT g.protocol_app_node_id, pan.source_id AS dataset_id,
COUNT(DISTINCT gene_id) AS num_genes,
0.05 / COUNT(DISTINCT gene_id) AS high_significance_threshold,
to_char(0.05 / COUNT(DISTINCT gene_id), '9.99EEEE') AS high_significance_threshold_display,
1.0 / COUNT(DISTINCT gene_id) AS moderate_significance_threshold,
to_char(1.0 / COUNT(DISTINCT gene_id), '9.99EEEE') AS moderate_significance_threshold_display
FROM Results.GeneAssociation g, Study.ProtocolAppNode pan
WHERE pan.protocol_app_node_id = g.protocol_app_node_id
GROUP BY (g.protocol_app_node_id, dataset_id)
);

CREATE INDEX GAC_PAN_IDX ON NIAGADS.GeneAssociationCorrection(protocol_app_node_id);
CREATE INDEX GAC_DATASET_IDX ON NIAGADS.GeneAssociationCorrection(dataset_id);
