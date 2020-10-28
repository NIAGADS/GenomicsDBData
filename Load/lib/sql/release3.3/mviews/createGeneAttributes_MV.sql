--DROP MATERIALIZED VIEW NIAGADS.GeneAttributes CASCADE;

CREATE EXTENSION btree_gist;

CREATE MATERIALIZED VIEW NIAGADS.GeneAttributes AS (
SELECT gf.na_feature_id, g.gene_id, gf.source_id, g.gene_symbol,
replace(gf.gene_type, '_',' ') AS gene_type,
nas.chromosome, nl.start_min, nl.end_max, nl.is_reversed::text::boolean AS is_reversed
FROM DoTS.GeneFeature gf, DoTS.Gene g, DoTS.GeneInstance gi,
DoTS.NALocation nl, DoTS.ExternalNASequence nas
WHERE gf.na_feature_id = gi.na_feature_id 
AND gi.gene_id = g.gene_id
AND nas.na_sequence_id = gf.na_sequence_id
AND nl.na_feature_id = gf.na_feature_id);

CREATE INDEX GENE_ATTRIBUTES_IND01 ON NIAGADS.GeneAttributes(source_id, na_feature_id, gene_symbol, gene_type);
CREATE INDEX GENE_ATTRIBUTES_IND02 ON NIAGADS.GeneAttributes USING GIST(chromosome, numrange(start_min, end_max, '[]'));

GRANT SELECT ON NIAGADS.GeneAttributes TO genomicsdb;
