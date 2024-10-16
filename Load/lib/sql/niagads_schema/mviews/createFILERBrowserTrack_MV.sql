DROP MATERIALIZED VIEW IF EXISTS NIAGADS.FILERBRowserTracks;

CREATE MATERIALIZED VIEW NIAGADS.FILERBrowserTracks AS (
WITH xdbr AS (
SELECT r.external_database_release_id FROM 
SRes.ExternalDatabase d, SRes.ExternalDatabaseRelease r
WHERE d.name = 'FILER' 
AND d.external_database_id = r.external_database_id),
FeatureTypes AS (
SELECT pan.source_id AS track,
regexp_replace(multi_replace(name, ARRAY['eQTL eQTL', 'sQTL sQTL', '_', '-histone-mark', ' replicated peaks', ' peaks'], ARRAY['eQTL', 'sQTL', ' ', '','', '']),' \(.+?\)', '', 'g') AS track_name,
CASE
WHEN track_summary->>'classification' LIKE '%CTCF%' THEN 'chromatin domain boundary (CTCF) site'
WHEN track_summary->>'classification' LIKE '%histone%' THEN 'histone modification'
WHEN track_summary->>'classification' LIKE '%start sites%' THEN 'transcription start site (TSS)'
WHEN track_summary->>'classification' LIKE '%ATAC%' THEN 'accessible chromatin'
WHEN track_summary->>'classification' LIKE '%ChIP-seq protein%' THEN 'transcription factor binding site (TFBS)'
WHEN track_summary->>'classification' LIKE '%eCLIP%' THEN 'RNA binding proteins (RBPs)'
WHEN track_summary->>'classification' LIKE '%DNase%' THEN 'DNase hypersensitive sites (DHSs)'
WHEN track_summary->>'classification' LIKE '%eQTL%' THEN 'expression QTL'
WHEN track_summary->>'classification' LIKE '%sQTL%' THEN 'splicing QTL'
WHEN track_summary->>'classification' LIKE '%microRNA%' THEN 'microRNA'
END AS feature_type
FROM Study.ProtocolAppNode pan, xdbr
WHERE xdbr.external_database_release_id = pan.external_database_release_id
AND pan.track_summary IS NOT NULL
) 
SELECT ft.track,
LOWER(replace(regexp_replace(ft.feature_type, ' \(.+?\)', '', 'g'), ' ', '_')) AS track_type,
pan.track_summary->>'data_source' AS data_source,
pan.name,
jsonb_build_object(
'name', ft.track || ': ' || ft.track_name,
'description', multi_replace(description, ARRAY['eQTL eQTL', 'sQTL sQTL', '_'], ARRAY['eQTL', 'sQTL', ' ']),
'track', pan.source_id,
'track_type', CASE WHEN name ILIKE '%qtl%' THEN 'qtl' ELSE 'annotation' END,
--'feature_type', LOWER(replace(regexp_replace(ft.feature_type, ' \(.+?\)', ''), ' ', '_')),
'track_type_display', CASE WHEN ft.feature_type LIKE '%QTL%' THEN 'xQTL' ELSE 'Functional Genomics' END,
'feature_type', ft.feature_type,
'label', truncate_str(ft.track_name, 40),
'format',
CASE WHEN split_part(pan.track_summary->>'file_format', ' ', 2) LIKE '%Peak%' THEN LOWER(split_part(pan.track_summary->>'file_format', ' ', 2))
WHEN split_part(pan.track_summary->>'file_format', ' ', 2) = 'bed13' AND name ILIKE '%qtl%' THEN 'bed3+10'
WHEN split_part(pan.track_summary->>'file_format', ' ', 2) = 'bed16' AND name ILIKE '%qtl%' THEN 'bed3+13'
ELSE 'bed' END,
'url', track_summary->>'processed_file_download_url',
'indexURL', track_summary->>'processed_file_download_url' || '.tbi',
'data_source', split_part(pan.track_summary->>'data_source', '_', 1),
'repository', 'NIAGADS (FILER)',
'biosample_characteristics', (track_summary->'biosample')::jsonb - 'term' - 'system' || jsonb_build_object('biosample', track_summary->'biosample'->>'term') || jsonb_build_object('anatomical_system', track_summary->'biosample'->>'system'),
'experimental_design', jsonb_build_object(
        'assay', track_summary->>'assay',
        'antibody_target', CASE WHEN track_summary->>'antibody' LIKE 'Not applicable%' THEN NULL ELSE replace(track_summary->>'antibody', '-human', '') END)) AS track_config

FROM Study.ProtocolAppNode pan, xdbr, FeatureTypes ft
WHERE xdbr.external_database_release_id = pan.external_database_release_id
AND ft.track = pan.source_id
AND pan.track_summary IS NOT NULL
-- temporary filter out cell lines
AND pan.track_summary::text NOT LIKE '%cell line%'
);

GRANT SELECT ON niagads.filerbrowsertracks TO genomicsdb, comm_wdk_w, gus_r;

