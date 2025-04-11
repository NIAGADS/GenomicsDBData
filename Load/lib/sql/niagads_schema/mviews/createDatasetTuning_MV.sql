DROP MATERIALIZED VIEW IF EXISTS NIAGADS.NeuropathologyTrackCategories;
DROP MATERIALIZED VIEW IF EXISTS NIAGADS.ProtocolAppNodeCharacteristic CASCADE;
--DROP MATERIALIZED VIEW IF EXISTS NIAGADS.TrackAttributes;
--DROP MATERIALIZED VIEW IF EXISTS NIAGADS.DatasetAttributes;


-------------------------------

CREATE MATERIALIZED VIEW IF NOT EXISTS NIAGADS.DatasetAttributes AS 
(
	SELECT 'study_' || s.study_id AS dataset_id
	, s.name
	, s.description
	, s.source_id AS accession
	, s.external_database_release_id
	, xdr.secondary_id_type AS category
	, s.approaches
	, s.attribution
	, xdr.version
	, build_link_attribute(xdr.id_url, xdr.id_url, '', NULL) AS resource_link
	, CASE WHEN s.source_id LIKE 'NG%' THEN build_link_attribute(source_id, xdr.download_url, NULL, NULL) 
	  ELSE build_link_attribute('', xdr.id_url, NULL, NULL) END AS accession_link
	FROM Study.Study s LEFT OUTER JOIN SRes.ExternalDatabaseRelease xdr 
	ON xdr.external_database_release_id = s.external_database_release_id
	UNION 
	SELECT 'db_' || external_database_release_id AS dataset_id
	, d.name
	, r.description
	, r.id_type AS accession
        , r.external_database_release_id
        , r.secondary_id_type AS category
        , NULL AS approaches
	, NULL AS attribution
        , r.version
        , build_link_attribute(r.id_url, r.id_url, '', NULL) AS resource_link
        , build_link_attribute(d.name, r.id_url, '', NULL) AS accession_link
	FROM SRes.ExternalDatabase d,
	SRes.ExternalDatabaseRelease r
	WHERE d.external_database_id = r.external_database_id
);


GRANT SELECT ON NIAGADS.DatasetAttributes TO gus_r, gus_w, comm_wdk_w;

CREATE INDEX DA_INDX01 ON NIAGADS.DatasetAttributes(accession);
CREATE INDEX DA_INDX02 ON NIAGADS.DatasetAttributes(category);
-------------------------------

CREATE MATERIALIZED VIEW IF NOT EXISTS NIAGADS.TrackAttributes AS (
SELECT da.dataset_id AS dataset_id,
da.accession AS dataset_accession,
da.version AS dataset_version,
pan.source_id AS track,
pan.name,
pan.description,
pan.protocol_app_node_id,
pan.attribution,
t.name AS category,
st.name AS subcategory
FROM Study.ProtocolAppNode pan,
NIAGADS.DatasetAttributes da,
Study.StudyLink sl,
SRes.OntologyTerm t,
SRes.OntologyTerm st
WHERE 'study_' || sl.study_id = da.dataset_id
AND sl.protocol_app_node_id = pan.protocol_app_node_id
AND t.ontology_term_id = pan.type_id
AND st.ontology_term_id = pan.subtype_id

UNION ALL

SELECT da.dataset_id AS dataset_id,
da.accession AS dataset_accession,
da.version AS dataset_version,
pan.source_id AS track,
pan.name,
pan.description,
pan.protocol_app_node_id,
pan.attribution,
t.name AS category,
st.name AS subcategory
FROM Study.ProtocolAppNode pan,
NIAGADS.DatasetAttributes da,
SRes.OntologyTerm t,
SRes.OntologyTerm st
WHERE 'db_' || pan.external_database_release_id = da.dataset_id
AND t.ontology_term_id = pan.type_id
AND st.ontology_term_id = pan.subtype_id
AND pan.protocol_app_node_id NOT IN (SELECT protocol_app_node_id FROM Study.StudyLink)

);


CREATE UNIQUE INDEX TRACKATT_IND01 ON NIAGADS.TrackAttributes(protocol_app_node_id);
CREATE INDEX TRACKTATT_IND02 ON NIAGADS.TrackAttributes(track);
CREATE INDEX TRACKTATT_IND03 ON NIAGADS.TrackAttributes(dataset_accession);
CREATE INDEX TRACKTATT_IND04 ON NIAGADS.TrackAttributes(category);
CREATE INDEX TRACKTATT_IND05 ON NIAGADS.TrackAttributes(subcategory);
CREATE INDEX TRACKTATT_IND06 ON NIAGADS.TrackAttributes USING gin(to_tsvector('english', name));
CREATE INDEX TRACKTATT_IND07 ON NIAGADS.TrackAttributes USING gin(to_tsvector('english', description));

GRANT SELECT ON NIAGADS.TrackAttributes TO gus_r, gus_w, comm_wdk_w;

-------------------------------


CREATE MATERIALIZED VIEW NIAGADS.ProtocolAppNodeCharacteristic AS (

WITH biomarkers AS (
SELECT c.protocol_app_node_id, 
CASE WHEN c.value IS NULL THEN (SELECT NAME FROM SRes.OntologyTerm WHERE ontology_term_id = c.ontology_term_id) ELSE c.value END AS characteristic,
'biomarker' AS characteristic_type
FROM Study.Characteristic c,
SRes.OntologyTerm q
WHERE q.ontology_term_id = c.qualifier_id
AND q.name = 'biomarker'),
annotatedBiomarkers AS (
SELECT protocol_app_node_id, characteristic, characteristic_type,
CASE WHEN characteristic = 'tau' THEN (SELECT replace(definition, 'Is a ', '') FROM SRes.OntologyTerm WHERE NAME = 't-tau measurement')
WHEN characteristic = 'pTau181' THEN (SELECT replace(definition, 'Is a ', '') FROM SRes.OntologyTerm WHERE NAME = 'p-tau measurement')
WHEN characteristic LIKE '%42%' THEN (SELECT replace(definition, 'Is the ', '') FROM SRes.OntologyTerm WHERE NAME = 'beta-amyloid 1-42 measurement')
WHEN characteristic = 'clusterin' THEN (SELECT definition FROM SRes.OntologyTerm WHERE NAME = 'clusterin measurement')
END AS definition
FROM Biomarkers b),

TempCharacteristics AS (
SELECT pan.protocol_app_node_id,
pan.source_id AS track,
CASE WHEN ot.name LIKE 'late onset%' THEN 'Alzheimer''s disease' ELSE REPLACE(ot.name, '_', '') END AS characteristic,
ot.ontology_term_id,
ot.source_id AS term_source_id,
q.name AS characteristic_type,
REPLACE(ot.definition, '"', '') AS definition,

CASE WHEN ot.name = 'autopsy-based diagnosis' THEN 'Diagnosis Type'
WHEN q.name = 'diagnosis' THEN 'Disease'
WHEN q.name LIKE 'Population' THEN 'Population'
WHEN q.name ILIKE 'apoe carrier%' THEN 'APOE &epsilon;4 Carrier Status' 
WHEN q.name = 'biomarker' AND pan.description LIKE '%CSF%' THEN 'CSF'
ELSE initcap(q.name) END AS filter_category,

CASE WHEN ot.name = 'autopsy-based diagnosis' THEN 'Diagnosis'
WHEN q.name LIKE 'neuropathology' THEN 'Diagnosis'
WHEN q.name ILIKE 'apoe carrier%' THEN 'Genotype'
ELSE initcap(q.name) END AS filter_category_parent,

FALSE AS is_value

FROM Study.Characteristic sc,
SRes.OntologyTerm ot,
SRes.OntologyTerm q,
Study.ProtocolAppNode pan
WHERE pan.protocol_app_node_id = sc.protocol_app_node_id
AND sc.ontology_term_id = ot.ontology_term_id
AND q.ontology_term_id = sc.qualifier_id
AND q.name NOT IN ('biomarker', 'phenotype')

UNION ALL 

SELECT pan.protocol_app_node_id,
pan.source_id AS track,
TRIM(sc.value) AS characteristic,
NULL AS ontology_term_id,
NULL AS term_source_id,
q.name AS characteristic_type,
NULL AS definition,
initcap(q.name) AS filter_category,
NULL AS filter_category_parent,
TRUE AS is_value
FROM Study.Characteristic sc,
SRes.OntologyTerm q,
Study.ProtocolAppNode pan
WHERE pan.protocol_app_node_id = sc.protocol_app_node_id
AND q.ontology_term_id = sc.qualifier_id
AND sc.value IS NOT NULL
AND q.name NOT SIMILAR TO  'biomarker|phenotype|covariate%'

UNION ALL  

SELECT protocol_app_node_id, track,
CASE WHEN characteristic LIKE 'age%' THEN 'age'
WHEN characteristic LIKE 'APOE%' THEN 'APOε4 carrier status or allele number'
ELSE TRIM(characteristic) END AS characteristic,
NULL AS ontology_term_id,
NULL AS term_source_id,
characteristic_type, 
NULL AS definition,
filter_category,
filter_category_parent,
is_value FROM (
SELECT pan.protocol_app_node_id,
pan.source_id AS track,
UNNEST(string_to_array(replace(sc.value, ' and ', ' '), ', ')) AS characteristic,
q.name AS characteristic_type,
'Covariate' AS filter_category,
'Study Design' filter_category_parent,
TRUE AS is_value
FROM Study.Characteristic sc,
SRes.OntologyTerm q,
Study.ProtocolAppNode pan
WHERE pan.protocol_app_node_id = sc.protocol_app_node_id
AND q.ontology_term_id = sc.qualifier_id
AND sc.value IS NOT NULL
AND q.name LIKE 'covariate%') v 

UNION ALL

SELECT pan.protocol_app_node_id,
pan.source_id AS track,
TRIM(sc.value) AS characteristic,
NULL AS ontology_term_id,
NULL AS term_source_id,
'covariate_list' AS characteristic_type,
NULL AS definition,
'CovariateList' AS filter_category,
'Study Design' filter_category_parent,
TRUE AS is_value
FROM Study.Characteristic sc,
SRes.OntologyTerm q,
Study.ProtocolAppNode pan
WHERE pan.protocol_app_node_id = sc.protocol_app_node_id
AND q.ontology_term_id = sc.qualifier_id
AND sc.value IS NOT NULL
AND q.name LIKE 'covariate%'

UNION ALL

SELECT b.protocol_app_node_id,
pan.source_id AS track,
b.characteristic,
NULL AS ontology_term_id,
NULL AS term_source_id,
'biomarker' AS characteristic_type,
b.definition,
CASE WHEN pan.name SIMILAR TO '%CSF%|%fluid%' THEN 'CSF' ELSE 'Blood' END AS filter_category,
'Biomarker' AS filter_category_parent,
TRUE AS is_value
FROM Study.ProtocolAppNode pan,
AnnotatedBiomarkers b
WHERE b.protocol_app_node_id = pan.protocol_app_node_id)

SELECT * FROM TempCharacteristics

UNION ALL

SELECT protocol_app_node_id, track, string_agg(characteristic, '//'),
NULL AS ontology_term, NULL AS term_source_id,
'full_list' AS characteristic_type,
NULL AS definition,
NULL AS filter_category,
NULL AS filter_category_parent,
NULL AS is_value
FROM TempCharacteristics
GROUP BY protocol_app_node_id, track

UNION ALL

SELECT protocol_app_node_id, track, string_agg(characteristic_type || '=' || characteristic, ';' ORDER BY characteristic_type),
NULL AS ontology_term, NULL AS term_source_id,
'full_info_string' AS characteristic_type,
NULL AS definition,
NULL AS filter_category,
NULL AS filter_category_parent,
NULL AS is_value
FROM (SELECT track, string_agg(characteristic, '//' ORDER by characteristic) AS characteristic, 
protocol_app_node_id, 
characteristic_type 
FROM TempCharacteristics 
WHERE characteristic_type NOT LIKE 'covariate%'
GROUP BY protocol_app_node_id, track, characteristic_type
) c
GROUP BY protocol_app_node_id, track

UNION ALL

SELECT protocol_app_node_id, track, string_agg(characteristic, '//'),
NULL AS ontology_term, NULL AS term_source_id,
'phenotype_list' AS characteristic_type,
NULL AS definition,
NULL AS filter_category,
NULL AS filter_category_parent,
NULL AS is_value
FROM TempCharacteristics
WHERE characteristic_type NOT LIKE 'covariate%'
GROUP BY protocol_app_node_id, track

);

GRANT SELECT ON NIAGADS.ProtocolAppNodeCharacteristic TO gus_r, gus_w, comm_wdk_w;

CREATE INDEX PAC_INDX01 ON NIAGADS.ProtocolAppNodeCharacteristic(track);
CREATE INDEX PAC_INDX02 ON NIAGADS.ProtocolAppNodeCharacteristic(protocol_app_node_id);
CREATE INDEX PAC_INDX03 ON NIAGADS.ProtocolAppNodeCharacteristic(characteristic, track);
CREATE INDEX PAC_INDX04 ON NIAGADS.ProtocolAppNodeCharacteristic(filter_category, track);
CREATE INDEX PAC_INDX05 ON NIAGADS.ProtocolAppNodeCharacteristic(filter_category, characteristic, track);
CREATE INDEX PAC_INDX06 ON NIAGADS.protocolAppNodeCharacteristic(filter_category, filter_category_parent, characteristic, track) WHERE track LIKE 'NG%';
CREATE INDEX PAC_INDX07 ON NIAGADS.ProtocolAppNodeCharacteristic(track) WHERE track LIKE 'NG%';

---------------------------


CREATE MATERIALIZED VIEW NIAGADS.NeuropathologyTrackCategories AS (
SELECT track, characteristic_type,  characteristic,
CASE --WHEN characteristic LIKE '%late onset%'  THEN 'LOAD'
WHEN characteristic LIKE '%Alz%' THEN 'AD/LOAD'
WHEN characteristic LIKE 'Progressive%' THEN 'PSP'
WHEN characteristic LIKE 'Fronto%' THEN 'FTD'
WHEN characteristic SIMILAR TO '%(plaques|dementia|memory|visuospatial|tangles|amyloid|aging|score|Braak|CERAD|measurement|impairment)%' THEN 'Other Neuropathology'
WHEN characteristic IN ('tau', 'pTau181', 'clusterin') THEN 'CSF Biomarker'
WHEN characteristic LIKE 'A%' AND characteristic_type = 'biomarker' THEN 'CSF Biomarker'
WHEN characteristic LIKE 'Lewy%' THEN 'LBD'
WHEN characteristic LIKE 'vascular%' THEN 'VBI'
WHEN characteristic LIKE 'Parkinson%' THEN 'PD'
ELSE characteristic END AS category_abbrev,

CASE --WHEN characteristic LIKE '%late onset%'  THEN 'late onset Alzheimer''s disease'
WHEN characteristic LIKE '%Alz%' THEN 'Alzheimer''s disease/late onset AD'
WHEN characteristic LIKE 'Progressive%' THEN 'Progressive supranuclear palsy'
WHEN characteristic LIKE 'Fronto%' THEN 'Frontotemporal demential'
WHEN characteristic SIMILAR TO '%(plaques|dementia|memory|visuospatial|tangles|amyloid|aging|score|Braak|CERAD|measurement|impairment)%' THEN 'AD/ADRD related neuropathology'
WHEN characteristic IN ('tau', 'pTau181', 'clusterin') THEN 'Cerebrospinal fluid biomarker for AD'
WHEN characteristic LIKE 'A%' AND characteristic_type = 'biomarker' THEN 'Cerebrospinal fluid biomarker for AD'
WHEN characteristic LIKE 'Lewy%' THEN 'Lewy body disease or neuropathology'
WHEN characteristic LIKE 'vascular%' THEN 'Vascular brain injury'
WHEN characteristic LIKE 'Parkinson%' THEN 'Parkinson''s disease'
ELSE characteristic END AS category
FROM NIAGADS.ProtocolAppNodeCharacteristic 
WHERE track LIKE 'NG0%' AND track NOT LIKE '%SKATO%'
AND characteristic_type IN ('diagnosis', 'neuropathology', 'biomarker')
AND characteristic NOT LIKE 'autopsy%');

GRANT SELECT ON NIAGADS.NeuropathologyTrackCategories TO gus_r, gus_w, comm_wdk_w;

CREATE INDEX NEUROPATH_IND01 ON NIAGADS.NeuropathologytrackCategories(track);
CREATE INDEX NEUROPATH_IND02 ON NIAGADS.NeuropathologytrackCategories(category_abbrev, track);
