-- migrate from NIAGADS views and Study Tables to Metadata.Track
-- temporary stop-gap

INSERT INTO Dataset.Track (track_id, data_store, name, description, genome_build, 
feature_type, is_download_only, searchable_text, provenance, experimental_design
) 

SELECT * FROM (
SELECT ta.track AS track_id,
'GENOMICS' AS data_store,
ta.name,
ta.description,
'GRCh38' AS genome_build,
'variant' AS feature_type,
FALSE AS is_download_only,
ta.name AS searchable_text, 


NULLIF (jsonb_strip_nulls(
jsonb_build_object(
'data_source', 'NHGRI-EBI CATALOG',
'accession', ta.dataset_accession
)), '{}') AS provenance,

NULLIF (jsonb_strip_nulls(
jsonb_build_object(
'data_category', 'curated',
'classification', 'genetic association',
'analysis', 'GWAS' )), '{}') AS experimental_design

FROM NIAGADS.TrackAttributes ta

LEFT OUTER JOIN Study.ProtocolAppNode pan ON pan.source_id = ta.track
WHERE ta.track = 'NHGRI_GWAS_CATALOG') a;


