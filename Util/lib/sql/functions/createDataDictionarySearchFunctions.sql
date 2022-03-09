CREATE OR REPLACE FUNCTION data_dict_text_search(searchTerm TEXT)
RETURNS TABLE (ontology_term TEXT,
	       ontology_term_id TEXT,
	       category TEXT,
	       description TEXT,
match_rank INTEGER,
	       matched_term TEXT

	       )

AS $$
BEGIN
RETURN QUERY

WITH
exact_term_match AS (
SELECT 1 AS match_ranking, name, ot.term_source_id, ot.category_level_1 AS category, ot.definition, NAME AS MATCH
FROM NIAGADS.DataDictionary ot
WHERE NAME ILIKE TRIM(searchTerm)),

exact_id_match AS (
SELECT 2 AS match_ranking, NAME, ot.term_source_id, ot.category_level_1 AS category, ot.definition, NAME AS MATCH
FROM NIAGADS.DataDictionary  ot
WHERE ot.term_source_id = TRIM(REPLACE(searchTerm, ':', '_'))),

partial_term_match AS (
SELECT 3 AS match_ranking, NAME, ot.term_source_id, ot.category_level_1 AS category, ot.definition, NAME AS MATCH
FROM NIAGADS.DataDictionary ot
WHERE NAME ILIKE '%' || TRIM(searchTerm) || '%'),

definition_match AS (
SELECT 4 AS match_ranking, NAME, ot.term_source_id, ot.category_level_1 AS category, ot.definition, ot.definition AS MATCH
FROM NIAGADS.DataDictionary ot
WHERE definition ILIKE '%' || TRIM(searchTerm) || '%'),

matches AS (
SELECT * FROM exact_term_match
UNION
SELECT * FROM exact_id_match
UNION
SELECT * FROM partial_term_match
UNION
SELECT * FROM definition_match
)

SELECT DISTINCT NAME::TEXT AS ontology_term, m.term_source_id::TEXT AS ontology_term_id, m.category::TEXT, m.definition::TEXT AS description,
first_value(match_ranking) OVER (PARTITION BY m.term_source_id ORDER BY match_ranking ASC) -1 AS match_rank,
first_value(match::TEXT) OVER (PARTITION BY m.term_source_id ORDER BY match_ranking ASC)::text AS matched_term
FROM matches M
ORDER BY match_rank ASC;

END; 

$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION data_dict_validate(searchTerm TEXT)
RETURNS TABLE (ontology_term TEXT,
	       ontology_term_id TEXT,
	       category TEXT,
	       description TEXT
	       )

AS $$
BEGIN
RETURN QUERY

WITH
exact_term_match AS (
SELECT 1 AS match_ranking, name, ot.term_source_id, ot.category_level_1 AS category, ot.definition, NAME AS MATCH
FROM NIAGADS.DataDictionary ot
WHERE NAME ILIKE TRIM(searchTerm)),

exact_id_match AS (
SELECT 2 AS match_ranking, NAME, ot.term_source_id, ot.category_level_1 AS category, ot.definition, NAME AS MATCH
FROM NIAGADS.DataDictionary  ot
WHERE ot.term_source_id = TRIM(REPLACE(searchTerm, ':', '_'))),

matches AS (
SELECT * FROM exact_term_match
UNION
SELECT * FROM exact_id_match
),

r AS (
SELECT DISTINCT NAME::TEXT AS ontology_term, m.term_source_id::TEXT AS ontology_term_id, m.category::TEXT,
m.definition::TEXT AS description,
first_value(match_ranking) OVER (PARTITION BY m.term_source_id ORDER BY match_ranking ASC) -1 AS match_rank,
first_value(match::TEXT) OVER (PARTITION BY m.term_source_id ORDER BY match_ranking ASC)::text AS matched_term
FROM matches M
ORDER BY match_rank ASC)

SELECT r.ontology_term, r.ontology_term_id, r.category, r.description FROM r;

END; 

$$ LANGUAGE plpgsql;
