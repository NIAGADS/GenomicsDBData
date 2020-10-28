DROP MATERIALIZED VIEW IF EXISTS NIAGADS.GenePathway;

CREATE MATERIALIZED VIEW NIAGADS.GenePathway AS (
SELECT ga.source_id AS gene_source_id,
p.name AS pathway_name,
p.source_id AS pathway_source_id
FROM SRes.PathwayNode pn,
NIAGADS.GeneAttributes ga,
SRes.Pathway p
WHERE p.pathway_id = pn.pathway_id
AND pn.row_id = ga.gene_id
);

CREATE INDEX GP_IND01 ON NIAGADS.GenePathway(gene_source_id, pathway_source_id);
CREATE INDEX GP_IND02 ON NIAGADS.GenePathway(pathway_source_id, gene_source_id);
CREATE INDEX GP_IND03 ON NIAGADS.GenePathway(pathway_name);
GRANT SELECT ON NIAGADS.GenePathway TO genomicsdb;
