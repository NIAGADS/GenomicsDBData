DROP MATERIALIZED VIEW IF EXISTS NIAGADS.DataDictionaryTerms;

CREATE MATERIALIZED VIEW NIAGADS.DataDictionaryTerms AS (
SELECT d.isa_ontology_term_id AS parent_id,
CASE WHEN pd.display_value IS NOT NULL THEN pd.display_value ELSE lower(isat.name) END AS parent_term,
CASE WHEN d.display_value IS NOT NULL THEN d.display_value WHEN ot.name = 'Ancestry' THEN 'ancestry' ELSE ot.name END AS display_value,
replace(d.synonyms, '|', ' // ') AS synonyms,
d.annotation AS notes,
ot.definition, ot.source_id, ot.uri
FROM NIAGADS.DataDictionary d,
SRes.OntologyTerm ot,
SRes.OntologyTerm isat,
NIAGADS.DataDictionary pd
WHERE d.ontology_term_id = ot.ontology_term_id
AND d.isa_ontology_term_id = isat.ontology_term_id
AND pd.ontology_term_id = d.isa_ontology_term_id
UNION ALL
SELECT NULL AS parent_id, 
NULL AS parent_term,
CASE WHEN d.display_value IS NOT NULL THEN d.display_value ELSE lower(ot.name) END AS display_value,
replace(d.synonyms, '|', ' // ') AS synonyms,
d.annotation AS notes,
ot.definition, ot.source_id, ot.uri
FROM NIAGADS.DataDictionary d,
SRes.OntologyTerm ot
WHERE d.ontology_term_id = ot.ontology_term_id
AND d.isa_ontology_term_id IS NULL);

GRANT SELECT ON NIAGADS.DataDictionaryTerms TO comm_wdk_w;