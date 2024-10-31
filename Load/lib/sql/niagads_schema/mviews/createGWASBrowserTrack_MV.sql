DROP MATERIALIZED VIEW IF EXISTS NIAGADS.GWASBrowserTracks CASCADE;
-- CASCADE will remove NIAGADS.SearchableBrowserTrackAnnotations

CREATE MATERIALIZED VIEW NIAGADS.GWASBrowserTracks AS (
WITH ExpDesign AS (
SELECT ta.track, jsonb_build_object(
'experimental_design', jsonb_build_object('covariates', string_agg(replace(c.characteristic, 'adjusted for ', ''), ' // ' ORDER BY c.characteristic)))
AS json_obj
FROM NIAGADS.TrackAttributes ta  LEFT OUTER JOIN NIAGADS.ProtocolAppNodeCharacteristic c 
ON c.track = ta.track
AND c.characteristic_type = 'covariate specification' 
WHERE ta.track LIKE 'NG0%' or ta.track LIKE 'GCST%' --gwas catalog study
GROUP BY ta.track),
Phenotypes AS (
SELECT ta.track,
replace(c.characteristic_type, 'biological sex', 'gender') AS characteristic_type,
string_agg(c.characteristic, ' // ' ORDER BY characteristic) AS characteristic
FROM NIAGADS.TrackAttributes ta LEFT OUTER JOIN NIAGADS.ProtocolAppNodeCharacteristic c
ON c.track = ta.track
AND c.characteristic_type != 'covariate specification' 
AND c.characteristic_type != 'covariate_list' 
AND c.characteristic_type != 'full_list'
AND c.characteristic_type != 'phenotype_list'
WHERE ta.track LIKE 'NG0%' or ta.track LIKE 'GCST%' --gwas catalog study
GROUP BY  ta.track, c.characteristic_type),
Biosamples AS (
SELECT track, jsonb_build_object('biosample_characteristics',
jsonb_object_agg(characteristic_type,
-- temporary fix for NULL population === 'European' 
CASE WHEN characteristic_type = 'population' AND characteristic IS NULL
THEN 'European'
ELSE characteristic END)) AS json_obj
FROM Phenotypes
GROUP BY track)
SELECT ta.track, 'gwas_summary_statistics' AS track_type, 'NIAGADS'::text AS data_source,
jsonb_build_object( 
'track', ta.track, 
'label', ta.name, 
'feature_type', 'variant', 
'track_type_display', 'GWAS Summary Statistics', 
'track_type', 'gwas_service', 
'endpoint', '@SERVICE_BASE_URI@/track/gwas', 
'data_source', 'NIAGADS',
'repository', 'NIAGADS (DSS)',
'consortium',
CASE WHEN ta.name LIKE '%ADSP%' OR ta.description LIKE '%ADSP%' THEN 'ADSP'
WHEN ta.name LIKE '%IGAP%' OR ta.description LIKE '%IGAP%' THEN 'IGAP'
WHEN ta.name LIKE '%ADGC%' OR ta.description LIKE '%ADGC%' THEN 'ADGC'
ELSE NULL END,
'description', ta.description, 
'name', ta.name || ' (' || ta.attribution || ')') ||
b.json_obj || d.json_obj AS track_config
FROM NIAGADS.TrackAttributes ta, Biosamples b, ExpDesign d
WHERE b.track = ta.track AND d.track = ta.track);

GRANT SELECT ON NIAGADS.GWASBrowserTracks TO gus_r, comm_wdk_w, genomicsdb;
