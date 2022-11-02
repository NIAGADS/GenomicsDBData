DROP MATERIALIZED VIEW IF EXISTS NIAGADS.SearchableBrowserTrackAnnotations;

CREATE MATERIALIZED VIEW NIAGADS.SearchableBrowserTrackAnnotations AS (
SELECT * FROM (
SELECT DISTINCT 'biosample_characteristic' AS category, 
replace(initcap(jsonb_object_keys(track_config->'biosample_characteristics')), 'Apoe', 'APOE') AS column_name,
jsonb_object_keys(track_config->'biosample_characteristics') AS field
FROM NIAGADS.GWASBrowserTracks
UNION
SELECT 'experimental_design' AS category, 'Covariates' AS column_name, 'covariates' AS field
UNION 
-- FILER
SELECT 'biosample_characteristic' AS category, unnest(ARRAY['Biosample', 'Tissue', 'Anatomical System']) AS column_name, 
replace(lower(unnest(ARRAY['Biosample', 'Tissue', 'Anatomical System'])), ' ', '_') AS field
UNION
SELECT 'experimental_design' AS category, unnest(ARRAY['Assay', 'Antibody Target']) AS column_name,
replace(lower(unnest(ARRAY['Assay', 'Antibody Target'])), ' ', '_') AS field) a 
ORDER BY category, custom_sort(ARRAY['Diagnosis', 'Neuropathology', 'Population', 'Assay', 'Antibody Target', 'Biosample', 'Anatomical System', 'Tissue', 'Tissue'], a.column_name)
);

GRANT SELECT ON NIAGADS.SearchableBrowserTrackAnnotations to gus_r, comm_wdk_w, genomicsdb;

