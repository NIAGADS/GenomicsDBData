DROP MATERIALIZED VIEW IF EXISTS NIAGADS.ProtocolAppNodeCharacteristic;

CREATE  MATERIALIZED VIEW NIAGADS.ProtocolAppNodeCharacteristic AS (


SELECT
    pan.protocol_app_node_id,
    CASE
        WHEN sc.value IS NOT NULL THEN sc.value
        WHEN (ot.display_term IS NOT NULL)
        THEN (ot.display_term)::text
        ELSE REPLACE((ot.name)::text, '_'::text, ' '::text)
    END                                                 AS characteristic,
    ot.source_id                                        AS characteristic_source_id,
    ot.category                                         AS characteristic_type,
    REPLACE((ot.definition)::text, '"'::text, ''::text) AS characteristic_definition
FROM
    study.characteristic sc,
    sres.ontologyterm ot,
    study.protocolappnode pan
WHERE pan.protocol_app_node_id = sc.protocol_app_node_id
    AND 
            sc.ontology_term_id = ot.ontology_term_id

            UNION 
            
	    SELECT
	    pan.protocol_app_node_id,

            sc.value AS characteristic,
	    
	    NULL                                  AS characteristic_source_id,
	    ot.name                                         AS characteristic_type,
	    NULL AS characteristic_definition
	    FROM
	    study.characteristic sc,
	    sres.ontologyterm ot,
	    study.protocolappnode pan
	    WHERE pan.protocol_app_node_id = sc.protocol_app_node_id
	    AND 
            sc.qualifier_id = ot.ontology_term_id
	    AND sc.ontology_term_id IS NULL
	    );

	    CREATE INDEX NG_PAN_CHARACTERISTIC_IND01 ON NIAGADS.ProtocolAppNodeCharacteristic(protocol_app_node_id, characteristic_type, characteristic);

	    GRANT SELECT ON NIAGADS.ProtocolAppNodeCharacteristic TO gus_r;
	    GRANT SELECT ON NIAGADS.ProtocolAppNodeCharacteristic TO gus_w;
	    GRANT SELECT ON NIAGADS.ProtocolAppNodeCharacteristic TO genomicsdb;

