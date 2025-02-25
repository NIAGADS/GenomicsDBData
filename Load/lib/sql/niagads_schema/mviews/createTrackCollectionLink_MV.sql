DROP MATERIALIZED VIEW IF EXISTS NIAGADS.TrackCollectionLink;

CREATE MATERIALIZED VIEW NIAGADS.TrackCollectionLink AS (
SELECT * FROM (
WITH NIAGADSTracks AS (
SELECT protocol_app_node_id
FROM Study.ProtocolAppNode pan,
SRes.ExternalDatabaseRelease xdbr,
SRes.ExternalDatabase d
WHERE d.name = 'NIAGADS' 
AND xdbr.external_database_id = d.external_database_id 
AND xdbr.external_database_release_id = pan.external_database_release_id)


SELECT nt.protocol_app_node_id AS track_id, c.collection_id
FROM NIAGADS.TrackAttributes ta, NIAGADSTracks nt, NIAGADS.Collection c
WHERE ta.subcategory = 'QTL'
AND ta.protocol_app_node_id = nt.protocol_app_node_id
AND c.name = 'ADSP-FunGen-xQTL') q

UNION ALL

SELECT * FROM (
WITH NIAGADSTracks AS (
SELECT DISTINCT pan.protocol_app_node_id, pan.name
FROM Study.ProtocolAppNode pan,
Study.Characteristic c,
SRes.ExternalDatabaseRelease xdbr,
SRes.ExternalDatabase d
WHERE d.name = 'NIAGADS' 
AND xdbr.external_database_id = d.external_database_id 
AND xdbr.external_database_release_id = pan.external_database_release_id
AND c.ontology_term_id IN (SELECT ontology_term_id FROM SRes.OntologyTerm WHERE name LIKE '%Alz%')
AND c.protocol_app_node_id = pan.protocol_app_node_id)
SELECT nt.protocol_app_node_id AS track_id, c.collection_id
FROM NIAGADS.TrackAttributes ta, NIAGADSTracks nt, NIAGADS.Collection c
WHERE ta.subcategory like '%GWAS%'
AND ta.protocol_app_node_id = nt.protocol_app_node_id
AND c.name like 'AD-GWAS%') ad

UNION ALL

SELECT * FROM (
WITH NIAGADSTracks AS (
SELECT pan.protocol_app_node_id, pan.name
FROM Study.ProtocolAppNode pan,
SRes.ExternalDatabaseRelease xdbr,
SRes.ExternalDatabase d
WHERE d.name = 'NIAGADS' 
AND xdbr.external_database_id = d.external_database_id 
AND xdbr.external_database_release_id = pan.external_database_release_id),

ADTracks AS (
SELECT nt.protocol_app_node_id, nt.name
FROM NIAGADSTracks nt, Study.Characteristic c
WHERE c.ontology_term_id IN (SELECT ontology_term_id FROM SRes.OntologyTerm WHERE name LIKE '%Alz%')
AND c.protocol_app_node_id = nt.protocol_app_node_id),

ADRDTracks AS (
SELECT *
FROM NIAGADSTracks nt
WHERE protocol_app_node_id NOT IN (SELECT protocol_app_node_id FROM ADTracks))

SELECT DISTINCT nt.protocol_app_node_id AS track_id, c.collection_id
FROM NIAGADS.TrackAttributes ta, ADRDTracks nt, NIAGADS.Collection c
WHERE ta.subcategory like '%GWAS%'
AND ta.protocol_app_node_id = nt.protocol_app_node_id
AND c.name like 'ADRD-GWAS%') adrd

ORDER BY collection_id, track_id
);

CREATE INDEX CTL_IDX_01 ON NIAGADS.TrackCollectionLink(COLLECTION_ID);

GRANT SELECT ON NIAGADS.TrackCollectionLink TO comm_wdk_w, gus_r, gus_w;