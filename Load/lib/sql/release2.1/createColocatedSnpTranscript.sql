-- DROP MATERIALIZED VIEW Colocated SnpTranscript;

CREATE MATERIALIZED VIEW ColocatedSnpTranscript AS (
  SELECT s.source_id as snp_source_id
  , t.name AS transcript_source_id
  FROM Snp s
  , DoTS.ExternalNASequence nas
  , DoTS.Transcript t
  , DoTS.NAlocation nl
  WHERE t.na_sequence_id = nas.na_sequence_id
  AND t.na_feature_id = nl.na_feature_id
  AND nas.chromosome = s.chromosome
  AND s.start_min BETWEEN nl.start_min and nl.end_max
);

CREATE UNIQUE INDEX ColocatedSnpTranscript_IDX1 ON ColocatedSnpTranscript(transcript_source_id, snp_source_id);
CREATE INDEX ColocatedSnpTranscript_IDX2 ON ColocatedSnpTranscript(snp_source_id);