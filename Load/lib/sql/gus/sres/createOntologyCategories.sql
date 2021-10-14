

-- study design

UPDATE SRes.OntologyTerm SET search_qualifiers = '{"category":"study design"}'
WHERE ontology_term_id IN (
SELECT ontology_term_id 
FROM SRes.OntologyTerm WHERE NAME LIKE '%design%'
AND NAME NOT LIKE 'obsolete%'
AND source_id NOT LIKE 'SO:%'
AND NAME NOT IN ('study design execution', 'study design', 'study design dependent variable', 'array design')
AND source_id  NOT LIKE 'operation%' -- these are "design of something e.g., DNA vaccine"
AND source_id NOT LIKE 'topic%');

-- tissue

-- cell

UPDATE SRes.OntologyTerm SET search_qualifiers = '{"category": "cell type"}'::JSONB ||
(CASE WHEN source_id LIKE 'CL\_%' THEN '{"rank": 1}'
WHEN source_id LIKE 'BTO\_%' THEN '{"rank": 2}'
ELSE '{"rank":100}' END)::JSONB

WHERE ontology_term_id IN (
SELECT ontology_term_id
FROM SRes.OntologyTerm WHERE
NAME NOT LIKE 'obsolete%'
AND (source_id LIKE 'CL\_%'
OR ((source_id LIKE 'BTO%' OR source_id LIKE 'EFO%' OR source_id LIKE 'PO\_%') AND NAME LIKE '%cell'))
);


-- cell line

