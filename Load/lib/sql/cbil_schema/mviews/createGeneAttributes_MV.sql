DROP MATERIALIZED VIEW IF EXISTS CBIL.GeneAttributes CASCADE;

CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE MATERIALIZED VIEW CBIL.GeneAttributes AS (
WITH transcripts AS (	 
SELECT t.parent_id AS gene_feature_id,
COUNT(t.source_id) AS transcript_count
FROM DoTS.Transcript t
GROUP BY t.parent_id),
exons AS (SELECT t.parent_id AS gene_feature_id,
COUNT(e.source_id) AS exon_count
FROM DoTS.ExonFeature e, DoTS.Transcript t
WHERE e.parent_id = t.na_feature_id
GROUP BY t.parent_id
),
annotation AS (
SELECT gf.na_feature_id, g.gene_id, gf.source_id, g.gene_symbol,
replace(gf.gene_type, '_',' ') AS gene_type,
nas.source_id AS chromosome,
nl.start_min::bigint AS location_start,
nl.end_max::bigint AS location_end,
nl.is_reversed::text::boolean AS is_reversed,

find_bin_index(nas.source_id, nl.start_min::bigint, nl.end_max::bigint) AS bin_index,
find_bin_index(nas.source_id, nl.start_min::bigint - 100000, nl.end_max::bigint + 100000) AS bin_index_100kb_flank,
find_bin_index(nas.source_id, nl.start_min::bigint - 50000, nl.end_max::bigint + 50000) AS bin_index_50kb_flank,
find_bin_index(nas.source_id, nl.start_min::bigint - 200000, nl.end_max::bigint + 200000) AS bin_index_200kb_flank,

tn.name AS genus_species,
CASE WHEN tn.name LIKE 'Homo%' THEN 'Human' ELSE 'Mouse' END AS organism,
t.ncbi_tax_id,
transcripts.transcript_count,
exons.exon_count
FROM DoTS.GeneFeature gf, DoTS.Gene g, DoTS.GeneInstance gi,
DoTS.NALocation nl, DoTS.ExternalNASequence nas,  SRes.TaxonName tn, SRes.taxon t,
transcripts, exons
WHERE gf.na_feature_id = gi.na_feature_id
AND gi.gene_id = g.gene_id
AND nas.na_sequence_id = gf.na_sequence_id
AND nl.na_feature_id = gf.na_feature_id
AND nas.taxon_id = tn.taxon_id
AND t.taxon_id = tn.taxon_id
AND transcripts.gene_feature_id = gf.na_feature_id
AND exons.gene_feature_id = gf.na_feature_id)
SELECT a.*, dbr.remark AS annotation FROM  Annotation a LEFT OUTER JOIN SRes.DBRef dbr
ON dbr.PRIMARY_IDENTIFIER = a.gene_id::text
);

CREATE INDEX GENE_ATTRIBUTES_SOURCEID ON CBIL.GeneAttributes USING HASH(source_id);
CREATE INDEX GENE_ATTRIBUTES_SYMBOL ON CBIL.GeneAttributes(gene_symbol);
CREATE INDEX GENE_ATTRIBUTES_SPAN ON CBIL.GeneAttributes USING GIST(chromosome, int8range(location_start, location_end, '[]'));
CREATE INDEX GENE_ATTRIBUTES_ANNOTATION ON CBIL.GeneAttributes USING GIN(annotation jsonb_path_ops);
CREATE INDEX GENE_ATTRIBUTES_TAXON ON CBIL.GeneAttributes(genus_species);

CREATE INDEX GENE_ATTRIBUTES_PK ON CBIL.GeneAttributes(gene_id);
CREATE INDEX GENE_ATTRIBUTES_PK_TABLE_LOOKUP ON CBIL.GeneAttributes(gene_id, source_id, gene_symbol);

CREATE INDEX GENE_ATTRIBUTES_TYPE ON CBIL.GeneAttributes USING HASH(gene_type);
CREATE INDEX GENE_ATTRIBUTES_BIN_INDEX ON CBIL.GeneAttributes USING GIST(bin_index);

GRANT SELECT ON CBIL.GeneAttributes TO gus_r, gus_w, comm_wdk_w;
