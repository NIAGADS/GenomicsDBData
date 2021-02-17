DROP MATERIALIZED VIEW IF EXISTS NIAGADS.ExonAttributes;

CREATE MATERIALIZED VIEW NIAGADS.ExonAttributes AS (
SELECT e.na_feature_id AS exon_feature_id,
e.source_id AS exon_source_id,
e.order_number AS exon_order_number,
t.gene_feature_id,
t.gene_source_id,
t.transcript_feature_id,
t.transcript_source_id,
s.source_id AS chromosome,
loc.start_min::int AS location_start,
loc.end_max::int AS location_end,
find_bin_index(s.source_id, loc.start_min::bigint, loc.start_max::bigint) AS bin_index
FROM DoTS.ExonFeature e,
DoTS.ExternalNASequence s,
DoTS.NALocation loc,
NIAGADS.TranscriptAttributes t
WHERE e.na_feature_id = loc.na_feature_id
AND s.na_sequence_id = e.na_sequence_id
AND e.parent_id = t.transcript_feature_id
);

CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE INDEX EXON_ATTRIBUTES_IND07 ON NIAGADS.ExonAttributes(exon_source_id, transcript_feature_id, gene_feature_id);
CREATE INDEX EXON_ATTRIBUTES_IND06 ON NIAGADS.ExonAttributes(chromosome);
CREATE INDEX EXON_ATTRIBUTES_IND05 ON NIAGADS.ExonAttributes(exon_source_id);
CREATE INDEX EXON_ATTRIBUTES_IND01 ON NIAGADS.ExonAttributes(transcript_source_id);
CREATE INDEX EXON_ATTRIBUTES_IND02 ON NIAGADS.ExonAttributes(gene_source_id);
CREATE INDEX EXON_ATTRIBUTES_IND03 ON NIAGADS.ExonAttributes USING GIST(numrange(location_start, location_end, '[]'));
CREATE INDEX EXON_ATTRIBUTES_IND04 ON NIAGADS.ExonAttributes USING GIST(bin_index);

GRANT SELECT ON NIAGADS.ExonAttributes TO comm_wdk_w, gus_r, gus_w;
