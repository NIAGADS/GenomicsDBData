DROP MATERIALIZED VIEW SnpGwasSummary;

CREATE MATERIALIZED VIEW SnpGwasSummary AS (
SELECT * FROM (
WITH IGAP AS (
SELECT source_id, true AS is_significant FROM 
SnpGwasResults
WHERE resource_accession = 'NG00036'
AND log_pvalue >= -1 * log(5 * 10 ^ (-8))
),

ADGC AS (
SELECT source_id, true AS is_significant FROM 
SnpGwasResults
WHERE resource_accession = 'NG00027'
AND log_pvalue >= -1 * log(5 * 10 ^ (-8))
),

NIAGADS AS (
SELECT source_id, true AS is_significant FROM 
SnpGwasResults
WHERE log_pvalue >= -1 * log(5 * 10 ^ (-8))
)

SELECT DISTINCT s.source_id
, i.is_significant AS igap_is_significant
, a.is_significant AS adgc_is_significant
, n.is_significant AS niagads_is_significant
FROM Snp s 
LEFT OUTER JOIN IGAP i ON s.source_id = i.source_id
LEFT OUTER JOIN ADGC a ON s.source_id = a.source_id
LEFT OUTER JOIN NIAGADS n ON s.source_id = n.source_id) k
);

CREATE UNIQUE INDEX SnpGwasSummary_ind01 ON SnpGwasSummary(source_id);
CREATE INDEX SnpGwasSummary_ind02 ON SnpGwasSummary(source_id) WHERE igap_is_significant;
CREATE INDEX SnpGwasSummary_ind03 ON SnpGwasSummary(source_id) WHERE adgc_is_significant;
CREATE INDEX SnpGwasSummary_ind04 ON SnpGwasSummary(source_id) WHERE niagads_is_significant;

GRANT SELECT ON SnpGwasSummary TO GenomicsDB;
