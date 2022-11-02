CREATE MATERIALIZED VIEW NIAGADS.FILERBrowserTracks AS (
WITH xdbr AS (
SELECT r.external_database_release_id FROM 
SRes.ExternalDatabase d, SRes.ExternalDatabaseRelease r
WHERE d.name = 'FILER' 
AND d.external_database_id = r.external_database_id),
FeatureTypes AS (
SELECT pan.source_id AS track,
regexp_replace(multi_replace(name, ARRAY['eQTL eQTL', 'sQTL sQTL', '_'], ARRAY['eQTL', 'sQTL', ' ']),' \(.+?\)', '') AS track_name,
CASE
WHEN track_summary->>'classification' LIKE '%CTCF%' THEN 'chromatin conformation'
WHEN track_summary->>'classification' LIKE '%histone%' THEN 'histone modification'
WHEN track_summary->>'classification' LIKE '%start sites%' THEN 'transcription start site (TSS)'
WHEN track_summary->>'classification' LIKE '%ATAC%' THEN 'accessible chromatin'
WHEN track_summary->>'classification' LIKE '%ChIP-seq protein%' THEN 'transcription factor binding site (TFBS)'
WHEN track_summary->>'classification' LIKE '%eCLIP%' THEN 'RNA binding proteins (RBPs)'
WHEN track_summary->>'classification' LIKE '%DNase%' THEN 'DNase hypersensitive sites (DHSs)'
WHEN track_summary->>'classification' LIKE '%eQTL%' THEN 'eQTL'
WHEN track_summary->>'classification' LIKE '%sQTL%' THEN 'sQTL'
WHEN track_summary->>'classification' LIKE '%microRNA%' THEN 'microRNA'
END AS feature_type
FROM Study.ProtocolAppNode pan, xdbr
WHERE xdbr.external_database_release_id = pan.external_database_release_id
AND pan.track_summary IS NOT NULL
) 
SELECT ft.track,
LOWER(replace(regexp_replace(ft.feature_type, ' \(.+?\)', ''), ' ', '_')) AS track_type,
pan.track_summary->>'data_source' AS data_source,
pan.name,
jsonb_build_object(
'name', ft.track_name,
'description', multi_replace(description, ARRAY['eQTL eQTL', 'sQTL sQTL', '_'], ARRAY['eQTL', 'sQTL', ' ']),
'track', pan.source_id,
'label', truncate_str(ft.track_name, 40),
'format', 'bed',
'path', track_summary->>'processed_file_download_url',
'source', pan.track_summary->>'data_source' || ' (FILER)',
'biosample_characteristics', track_summary->'biosample',
'experimental_design', jsonb_build_object(
        'assay', track_summary->>'assay',
        'antibody_target', CASE WHEN track_summary->>'antibody' LIKE 'Not applicable%' THEN NULL ELSE replace(track_summary->>'antibody', '-human', '') END)
)
FROM Study.ProtocolAppNode pan, xdbr, FeatureTypes ft
WHERE xdbr.external_database_release_id = pan.external_database_release_id
AND ft.track = pan.source_id
AND pan.track_summary IS NOT NULL
-- temporary filter out cell lines
AND pan.track_summary::text NOT LIKE '%cell line%'
);

GRANT SELECT ON niagads.filerbrowsertracks TO genomicsdb, comm_wdk_w, gus_r;

