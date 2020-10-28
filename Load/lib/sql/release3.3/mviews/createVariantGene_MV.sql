DROP MATERIALIZED VIEW IF EXISTS NIAGADS.VariantGene;

CREATE MATERIALIZED VIEW NIAGADS.VariantGene AS (
       SELECT sf.primary_key AS variant_primary_key,
       string_agg('<a href="@GENE_RECORD@' || ga.source_id || '">' || ga.gene_symbol || '</a>', ', ') AS colocated_gene_link,
       string_agg(ga.gene_symbol, '/') AS colocated_gene
       FROM DoTS.SnpFeature sf,
       NIAGADS.GeneAttributes ga
       WHERE sf.chromosome = ga.chromosome
       AND sf.position_start BETWEEN ga.start_min AND ga.end_max
       GROUP BY sf.primary_key
);

CREATE INDEX NVG_IND01 ON NIAGADS.VariantGene(variant_primary_key);

GRANT SELECT ON NIAGADS.VariantGene TO gus_w;
GRANT SELECT ON NIAGADS.VariantGene TO gus_r;
