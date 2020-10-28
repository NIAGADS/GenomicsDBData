DROP Materialized View ExomeArraySnp;

CREATE MATERIALIZED VIEW ExomeArraySnp AS (
SELECT DISTINCT s.source_id AS snp_source_id, sr.genetic_location AS exome_array_id
FROM Results.SegmentResult sr
, DoTS.ExternalNASequence nas
, SNP s
WHERE sr.genetic_location IS NOT NULL 
AND nas.na_sequence_id = sr.na_sequence_id
AND s.chromosome = nas.source_id
AND s.start_min = segment_start
);

GRANT SELECT ON ExomeArraySnp TO GenomicsDB;

CREATE INDEX ExomeArraySnp_ind01 ON ExomeArraySnp(exome_array_id);
CREATE INDEX ExomeArraySnp_ind02 ON ExomeArraySnp(snp_source_id);
