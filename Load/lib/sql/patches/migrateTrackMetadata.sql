-- migrate from NIAGADS views and Study Tables to Metadata.Track
-- temporary stop-gap

-- DELETE FROM Metadata.Track WHERE data_store = 'GENOMICS';

INSERT INTO Metadata.Track (track_id, data_store, name, description, genome_build, 
feature_type, is_download_only, searchable_text, 
subject_phenotypes,
biosample_characteristics, 
file_properties,
provenance,
experimental_design,
cohorts)
SELECT * FROM (
WITH 
pubmed AS (
SELECT ta.track AS track_id,
NULLIF(split_part(da.attribution, '|', 2),'') AS pubmed_id
FROM NIAGADS.DatasetAttributes da, NIAGADS.TrackAttributes ta
WHERE da.accession = ta.dataset_accession),

disease AS (
SELECT track AS track_id, 
json_agg(jsonb_build_object('term', characteristic, 'term_id', term_source_id)) AS terms
FROM NIAGADS.ProtocolAppNodeCharacteristic
WHERE characteristic_type = 'diagnosis'
GROUP BY track_id),

genotype AS (
SELECT track AS track_id, 
json_agg(jsonb_build_object('term', characteristic, 'term_id', term_source_id)) AS terms
FROM NIAGADS.ProtocolAppNodeCharacteristic
WHERE characteristic_type = 'APOE carrier status'
GROUP BY track_id),

neuropathology AS (
SELECT track AS track_id, 
json_agg(jsonb_build_object('term', characteristic, 'term_id', term_source_id)) AS terms
FROM NIAGADS.ProtocolAppNodeCharacteristic
WHERE characteristic_type = 'neuropathology'
GROUP BY track_id),

sex AS (
SELECT track AS track_id, 
json_agg(jsonb_build_object('term', characteristic, 'term_id', term_source_id)) AS terms
FROM NIAGADS.ProtocolAppNodeCharacteristic
WHERE characteristic_type = 'biological sex'
GROUP BY track_id),

ethnicity AS (
SELECT track AS track_id, 
json_agg(jsonb_build_object('term', CASE WHEN characteristic IS NULL THEN 'European' ELSE characteristic END, 'term_id', term_source_id)) AS terms
FROM NIAGADS.ProtocolAppNodeCharacteristic
WHERE characteristic_type = 'population'
GROUP BY track_id),

biomarker AS (
SELECT track AS track_id,
json_agg(characteristic) AS terms
FROM NIAGADS.ProtocolAppNodeCharacteristic
WHERE characteristic_type = 'biomarker'
GROUP BY track_id),

tissue AS (
SELECT track AS track_id,
json_agg(characteristic) AS terms
FROM NIAGADS.ProtocolAppNodeCharacteristic
WHERE characteristic_type = 'tissue'
GROUP BY track_id),

covariates AS (
SELECT track AS track_id,
json_agg(replace(characteristic, 'adjusted for ', '')) AS terms
FROM NIAGADS.ProtocolAppNodeCharacteristic
WHERE characteristic_type = 'covariate specification'
GROUP BY track_id)

SELECT ta.track AS track_id,
'GENOMICS' AS data_store,
ta.name,
ta.description,
'GRCh38' AS genome_build,
'variant' AS feature_type,
FALSE AS is_download_only,
ta.name || ';' || ta.description AS searchable_text, -- FIXME to include phenotypes, consortium, attribution, etc

NULLIF(jsonb_strip_nulls(
jsonb_build_object(
'disease', disease.terms, 
'neuropathology', neuropathology.terms,
'biological_sex', sex.terms,
'genotype', genotype.terms,
'ethnicity', ethnicity.terms)), '{}') AS subject_phenotypes,

NULLIF(jsonb_strip_nulls(jsonb_build_object('biomarker', biomarker.terms, 'tissue', tissue.terms)), '{}') 
AS biosample_characteristics,

NULLIF(jsonb_strip_nulls(jsonb_build_object(
'file_name', ta.track || '_pvalue_only.vcf.gz',
'url', 'https://www.niagads.org/genomics/files/gwas/' || ta.dataset_accession || '/' || ta.track || '_pvalue_only.vcf.gz',
'file_schema', 'annotated_vcf',
'file_format', 'vcf'
)), '{}') AS file_properties,

NULLIF (jsonb_strip_nulls(
jsonb_build_object(
'data_source', CASE WHEN ta.track LIKE 'NG0%' THEN 'NIAGADS DSS' ELSE 'NHGRI-EBI CATALOG' END,
'accession', ta.dataset_accession,
'pubmed_id', CASE WHEN pubmed.pubmed_id IS NULL THEN NULL ELSE ARRAY[pubmed.pubmed_id] END,
'attribution', pan.attribution,
'consortium', string_to_array(pan.track_summary->>'consortium', ',')
)), '{}') AS provenance,

NULLIF (jsonb_strip_nulls(
jsonb_build_object(
'data_category', 'summary statistics',
'classification', 'genetic association',
'is_lifted', CASE WHEN ta.track LIKE '%GRCh38' THEN TRUE ELSE NULL END,
'analysis', 'GWAS',
'covariates', covariates.terms )), '{}') AS experimental_design,
string_to_array(pan.track_summary->>'cohorts', ',') AS cohorts

FROM NIAGADS.TrackAttributes ta
LEFT OUTER JOIN sex ON sex.track_id = ta.track
LEFT OUTER JOIN disease ON disease.track_id = ta.track
LEFT OUTER JOIN neuropathology ON neuropathology.track_id = ta.track
LEFT OUTER JOIN genotype ON genotype.track_id = ta.track
LEFT OUTER JOIN ethnicity ON ethnicity.track_id = ta.track
LEFT OUTER JOIN biomarker ON biomarker.track_id = ta.track
LEFT OUTER JOIN tissue ON tissue.track_id = ta.track
LEFT OUTER JOIN covariates ON covariates.track_id = ta.track
LEFT OUTER JOIN pubmed ON pubmed.track_id = ta.track
LEFT OUTER JOIN Study.ProtocolAppNode pan ON pan.source_id = ta.track
WHERE ta.track LIKE 'NG0%' OR ta.track LIKE 'GCST%') a;