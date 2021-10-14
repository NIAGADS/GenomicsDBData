CREATE MATERIALIZED VIEW NIAGADS.OntologyTerm AS (
SELECT
    ontologyterm.ontology_term_id,
    ontologyterm.ontology_term_type_id,
    ontologyterm.name,
    ontologyterm.definition,
    ontologyterm.source_id,
    ontologyterm.category,
    ontologyterm.notes,
    ontologyterm.search_qualifiers
FROM
    sres.ontologyterm
WHERE
    ((
            ontologyterm.source_id)::text ~~ 'NO%'::text)
	    );
