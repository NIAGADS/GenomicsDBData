DROP MATERIALIZED VIEW IF EXISTS NIAGADS.ResourceAttributes;
DROP MATERIALIZED VIEW IF EXISTS NIAGADS.TrackAttributes;

-------------------------------

CREATE MATERIALIZED VIEW NIAGADS.ResourceAttributes AS 
(
	SELECT s.study_id AS resource_collection_id
	, s.name AS NAME
	, s.description AS description
	, s.source_id AS source_id 
	, s.external_database_release_id
	, ot.name AS TYPE
	, s.approaches
	, xdr.version
	, xdr.download_url
	, CASE WHEN s.source_ID LIKE 'NG%' THEN '/datasets/' || LOWER(s.source_id) ELSE xdr.id_url END AS external_url
	, xdr.file_name
	FROM Study.Study s LEFT OUTER JOIN SRes.ExternalDatabaseRelease xdr 
	ON xdr.external_database_release_id = s.external_database_release_id,
	SRes.OntologyTerm ot
	WHERE ot.ontology_term_id = s.category_id
);


GRANT SELECT ON NIAGADS.ResourceAttributes TO GenomicsDB;


-------------------------------

CREATE MATERIALIZED VIEW NIAGADS.TrackAttributes AS (
SELECT * FROM (
WITH Tracks AS (
SELECT pan.protocol_app_node_id
, c.study_id AS resource_id
, c.source_id AS resource_source_id
, pan.source_id AS track
, pan.name
, pan.description
, pan.uri AS download_url
, replace(t.name, '_', ' ' ) AS track_type
, pan.subtype_id
FROM Study.StudyLink sl
, Study.ProtocolAppNode pan
, Study.Study c
, SRes.OntologyTerm t
WHERE c.study_id = sl.study_id
AND sl.protocol_app_node_id = pan.protocol_app_node_id
AND ((c.source_id LIKE 'NG%' AND pan.source_id LIKE 'NG%') OR (c.source_id NOT LIKE 'NG%')) -- don't link other resources associated via analyses to NIAGADS accessions
AND  t.ontology_term_id = pan.type_id)
SELECT r.*
, replace(t.name, '_' , ' ') AS track_subtype
FROM
Tracks r LEFT OUTER JOIN SRes.OntologyTerm t
ON r.subtype_id = t.ontology_term_id) a
);


CREATE UNIQUE INDEX TRACKATT_IND01 ON NIAGADS.TrackAttributes(protocol_app_node_id);
CREATE INDEX TRACTATT_IND02 ON NIAGADS.TrackAttributes(track, protocol_app_node_id);
CREATE INDEX TRACTATT_IND09 ON NIAGADS.TrackAttributes(resource_source_id, track);
CREATE INDEX TRACTATT_IND03 ON NIAGADS.TrackAttributes(track_subtype, protocol_app_node_id);
CREATE INDEX TRACTATT_IND04 ON NIAGADS.TrackAttributes(track_subtype, track);
CREATE INDEX TRACTATT_IND05 ON NIAGADS.TrackAttributes USING gin(to_tsvector('english', name));
CREATE INDEX TRACTATT_IND06 ON NIAGADS.TrackAttributes USING gin(to_tsvector('english', description));

GRANT SELECT ON NIAGADS.TrackAttributes TO GenomicsDB;

