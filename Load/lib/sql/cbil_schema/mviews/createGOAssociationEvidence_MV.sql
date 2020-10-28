-- joins go association information w/evidence so sub tables can be produced
DROP MATERIALIZED VIEW IF EXISTS CBIL.GOAssociationEvidence;
 
CREATE MATERIALIZED VIEW CBIL.GOAssociationEvidence AS
(
 WITH
            evidence_json AS
            (
                SELECT
                    gene_id,
                    go_term_id,
                    jsonb_array_elements_text(evidence)::jsonb AS json
                FROM
                    CBIL.GOAssociation
            )
            ,
            mapped_evidence AS
            (
                SELECT
                    e.gene_id,
                    e.go_term_id,
                    CASE WHEN e.json->>'qualifier' = 'NOT|contributes_to' THEN 'does not contribute to'
 WHEN e.json->>'qualifier' = 'NOT|colocalizes_with' THEN 'does not colocalize with'
 WHEN e.json->>'qualifier' = 'involved_in' THEN 'is involved in'
 WHEN e.json->>'qualifier' = 'NOT|part_of' THEN 'is not part of'
 WHEN e.json->>'qualifier' = 'NOT|enables' THEN 'does not enable'
 WHEN e.json->>'qualifier' = 'part_of' THEN 'is part of'
ELSE replace(e.json->>'qualifier', '_', ' ')
END AS association_qualifier,
                    replace(e.json->>'annotation_source', '_', ' ') AS annotation_source,
                    jsonb_build_object('type', 'text',
                    'tooltip', (e.json->>'evidence_code')::text || ': ' || ot.name, 
                    'value', e.json->> 'go_evidence_code') AS evidence_code,
                    CASE
                        WHEN e.json->>'citation' LIKE 'PMID%'
                        THEN jsonb_build_object('type', 'link', 'url', '+PUBMED_URL+' || split_part
                            (e.json->>'citation', ':', 2), 'value', e.json->>'citation')
                        WHEN e.json->>'citation' LIKE 'GO_REF%'
                        THEN jsonb_build_object('type', 'text', 'tooltip', REPLACE(gref.abstract,
                            ' Further detailed information on this procedure, including how ISS annotations are made to protein isoforms, can be found at'
                            , ''), 'value', e.json->>'citation' || ': ' || gref.title)
                        WHEN e.json->>'citation' LIKE 'Reactome%'
                        THEN jsonb_build_object('type', 'link', 'url', '+REACTOME_PATHWAY_URL+' ||
                            split_part(e.json->>'citation', ':', 2), 'value', e.json->>'citation')
                        WHEN e.json->>'citation' LIKE 'DOI%'
                        THEN jsonb_build_object('type', 'link', 'url', '+DOI_URL+' || split_part
                            (e.json ->>'citation', ':', 2), 'value', LOWER(e.json->>'citation'))
                    END AS citation
                FROM
                    SRes.OntologyTerm ot,
                    evidence_json e
                LEFT OUTER JOIN
                    SRes.BibliographicReference gref
                ON
                    e.json->>'citation' = gref.source_id
                WHERE
                    ot.source_id = REPLACE(e.json->>'evidence_code', ':', '_')
            )
            ,
            final_evidence_json AS
            (
                SELECT
                    gene_id,
                    go_term_id,
                    jsonb_build_object('association_qualifier', association_qualifier, 'evidence_code', evidence_code, 'citation', citation, 'annotation_source', annotation_source ) AS json
                FROM
                    mapped_evidence
            )
        SELECT
	    ga.gene_id,
            ga.source_id,
            goa.go_term_id,
            CASE
                WHEN pot.name = 'biological_process'
                THEN 'BP'
                WHEN pot.name = 'molecular_function'
                THEN 'MF'
                ELSE 'CC'
            END                                                   AS ontology,
            string_agg(DISTINCT e.json->>'go_evidence_code', ',') AS go_evidence_code,
            jsonb_build_object('type', 'link', 'url', '+AMIGO_URL+' || REPLACE(ot.source_id, '_',':') || '#display-lineage-tab', 'value', REPLACE(ot.source_id, '_', ':')) AS go_accession,
            jsonb_build_object('type', 'text', 'tooltip',
            CASE
                WHEN LENGTH(ot.definition) > 297
                THEN LEFT(ot.definition, 297) || '...'
                ELSE ot.definition
            END , 'value', ot.name) AS term,
            jsonb_build_object('type', 'table', 'value', ga.gene_symbol || ' ' || string_agg(DISTINCT fej.json->>'association_qualifier', '|'), 'data', jsonb_agg(DISTINCT fej.json),
            'downloadable', false, 'attributes', jsonb_build_array(jsonb_build_object('name', 'association_qualifier', 'displayName', 'Association Qualifier',  'type', 'string',
            'help', 'explicit relationship between the gene and the GO term or a flag that modifies the interpretation of an association'),
            jsonb_build_object('name', 'evidence_code', 'displayName','Evidence Code', 'type', 'json_text',
            'help','mouse over for fuller description from the Evidence and Conclusion Ontology (ECO)'),
            jsonb_build_object('name', 'citation', 'displayName', 'Reference', 'type', 'json_text_or_link',
            'help', 'a single reference (publication, data resource, or protocol) in support of the annotation'), 
            jsonb_build_object('name', 'annotation_source', 'displayName', 'Assigned By', 'type', 'string',
            'help', 'attribution for the source of the annotation'))) AS evidence_table_dropdown
        FROM
            CBIL.GeneAttributes ga, -- just need source id and symbol
            SRes.OntologyTerm ot,
            SRes.OntologyTerm pot,
            CBIL.GOAssociation goa,
            evidence_json e,
            final_evidence_json fej
        WHERE
            ga.gene_id = goa.gene_id
        AND goa.go_term_id = ot.ontology_term_id
        AND pot.ontology_term_id = ot.ancestor_term_id
        AND e.gene_id = goa.gene_id
        AND e.go_term_id = goa.go_term_id
        AND fej.go_term_id = goa.go_term_id
        AND fej.gene_id = goa.gene_id
        GROUP BY
	    ga.gene_id,
	    ga.gene_symbol,
            ga.source_id,
            goa.go_term_id,
            ontology,
            e.go_term_id,
            ot.source_id,
            ot.definition,
            ot.name
            );

CREATE INDEX GO_ASSOCIATION_EVIDENCE_IND01 ON CBIL.GOAssociationEvidence(source_id);
CREATE INDEX GO_ASSOCIATION_EVIDENCE_IND02 ON CBIL.GOAssociationEvidence(go_term_id, source_id);
CREATE INDEX GO_ASSOCIATION_EVIDENCE_IND03 ON CBIL.GOAssociationEvidence(ontology);
