DROP MATERIALIZED VIEW SegmentResultSnp CASCADE;

CREATE MATERIALIZED VIEW SegmentResultSnp AS (
SELECT * FROM (
WITH Results AS (
SELECT sr.segment_result_id 
, sr.p_value
, sr.genetic_location AS exome_array_id
, sr.categorical_value AS allele
, s.source_id AS snp_source_id
, s.chromosome
, s.start_min
, pan.protocol_app_node_id AS resource_id
FROM Study.ProtocolAppNode pan
, Results.SegmentResult sr
, DoTS.ExternalNASequence nas
, SNP s
WHERE pan.source_id LIKE 'NG%'
AND pan.protocol_app_node_id = sr.protocol_app_node_id
AND nas.na_sequence_id = sr.na_sequence_id
AND nas.source_id = s.chromosome 
AND s.start_min = sr.segment_start),
RankedResults AS (
SELECT *
, ROW_NUMBER() OVER (PARTITION BY snp_source_id, resource_id ORDER BY p_value DESC) AS row_number
FROM results)
SELECT * FROM RankedResults WHERE row_number = 1
) a
);

CREATE INDEX sr_snpmap_ind01 ON SegmentResultSnp (snp_source_id);
CREATE INDEX sr_snpmap_ind02 ON SegmentResultSnp (resource_id, p_value);
CREATE INDEX sr_snpmap_ind03 ON SegmentResultSnp (chromosome, p_value, start_min);
CREATE INDEX sr_snpmap_ind04 ON SegmentResultSnp (chromosome, start_min);
CREATE INDEX sr_snpmap_ind06 ON SegmentResultSnp (p_value);
CREATE INDEX sr_snpmap_ind07 ON SegmentResultSnp (segment_result_id);

GRANT SELECT ON SegmentResultSnp TO GenomicsDB;
