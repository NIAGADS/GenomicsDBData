-- site search  -- one function for each record type

CREATE OR REPLACE FUNCTION ontology_text_search(searchTerm TEXT)
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
SELECT 1 AS match_ranking, name, ot.source_id, ot.category, ot.definition, name AS match
FROM SRes.OntologyTerm ot
WHERE name ILIKE TRIM(searchTerm)),

exact_id_match AS (
SELECT 2 AS match_ranking, NAME, ot.source_id, ot.category, ot.definition, NAME AS match
FROM SRes.OntologyTerm  ot
WHERE source_id = TRIM(REPLACE(searchTerm, ':', '_'))),

partial_term_match AS (
SELECT 3 AS match_ranking, NAME, ot.source_id, ot.category, ot.definition, NAME AS match
FROM SRes.OntologyTerm ot
WHERE NAME ILIKE '%' || TRIM(searchTerm) || '%'),

definition_match AS (
SELECT 4 AS match_ranking, NAME, ot.source_id, ot.category, ot.definition, ot.definition AS match
FROM SRes.OntologyTerm ot
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

SELECT DISTINCT NAME::TEXT AS ontology_term, m.source_id::TEXT AS ontology_term_id, m.category::TEXT, m.definition::TEXT AS description,
first_value(match_ranking) OVER (PARTITION BY m.source_id ORDER BY match_ranking ASC) -1 AS match_rank,
first_value(match::TEXT) OVER (PARTITION BY m.source_id ORDER BY match_ranking ASC)::text AS matched_term
FROM matches m
ORDER BY match_rank ASC;

END; 

$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION variant_text_search(searchTerm TEXT) 
RETURNS TABLE ( primary_key TEXT,
	      	display TEXT,
		record_type TEXT,
		match_rank INTEGER,
		matched_term TEXT,
		description TEXT
	     )
AS $$
BEGIN

RETURN QUERY 

WITH STerm AS (
SELECT searchTerm AS search_term, 
REPLACE(REPLACE(REPLACE(REPLACE(TRIM(searchTerm),'-', ':'), '/', ':'), 'chr', ''),'MT','M')::text AS term),

matched_variant AS (
--refsnp match (includes merges)
SELECT st.search_term, st.term, record_primary_key, 1 AS match_ranking
FROM STerm st, find_variant_by_refsnp(LOWER(st.term))
WHERE LOWER(st.term) LIKE 'rs%'

UNION

-- metaseq, include switching alleles
SELECT st.search_term, st.term, record_primary_key, 2 AS match_ranking
FROM STerm st, find_variant_by_metaseq_id_variations(st.term)
WHERE st.term LIKE '%:%' AND array_length(regexp_split_to_array(st.term, ':'),1) = 4

UNION

-- by position
SELECT st.search_term, st.term, record_primary_key, 3 AS match_ranking 
FROM STerm st, find_variant_by_position('chr' || split_part(st.term, ':', 1), split_part(st.term, ':', 2)::integer)
WHERE st.term LIKE '%:%' AND array_length(regexp_split_to_array(st.term, ':'),1) = 2
)

SELECT mv.record_primary_key AS primary_key, 
sa.display_metaseq_id || COALESCE(' (' || sa.ref_snp_id || ') ', '') AS display,
'variant' AS record_type,
mv.match_ranking,
CASE WHEN LOWER(mv.term) LIKE 'rs%' AND sa.ref_snp_id != LOWER(mv.term) THEN 'merged from: ' || LOWER(mv.term) 
WHEN LOWER(mv.term) LIKE 'rs%' THEN LOWER(mv.term)
ELSE mv.term END AS matched_term,
CASE WHEN sa.is_adsp_variant THEN 'ADSP VARIANT' ELSE 'VARIANT' END
|| ' // ' || sa.variant_class_abbrev
|| ' // Alleles: ' || sa.display_allele
|| COALESCE(' // ' || sa.most_severe_consequence, '')
|| COALESCE(' // ' || sa.msc_impact, '') AS description
FROM matched_variant mv, get_summary_annotation_by_primary_key(mv.record_primary_key) sa
ORDER BY mv.match_ranking ASC;

END; 

$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION gene_text_search(searchTerm TEXT) 
RETURNS TABLE ( primary_key CHARACTER VARYING,
	      	display TEXT,
		record_type TEXT,
		match_rank INTEGER,
		matched_term TEXT,
		description TEXT
	     )
AS $$
BEGIN

RETURN QUERY 

WITH gene_matches AS (
-- exact: source_id
SELECT ga.source_id, 1 AS match_ranking, ga.source_id AS matched_term
FROM CBIL.GeneAttributes ga
WHERE ga.source_id = TRIM(searchTerm)

UNION ALL

-- exact: gene_symbol
SELECT ga.source_id, 1 AS match_ranking, ga.gene_symbol AS matched_term
FROM CBIL.GeneAttributes ga
WHERE ga.gene_symbol = TRIM(searchTerm)

UNION ALL

-- partial: gene_symbol
SELECT ga.source_id, 2 AS match_ranking, ga.gene_symbol AS matched_term
FROM CBIL.GeneAttributes ga
WHERE ga.gene_symbol ILIKE '%' || TRIM(searchTerm) || '%'

UNION ALL

-- exact: entrez_id
SELECT ga.source_id, 1 AS match_ranking, (annotation->>'entrez_id')::text AS matched_term
FROM CBIL.GeneAttributes ga
WHERE (annotation->>'entrez_id')::text = TRIM(searchTerm)

UNION ALL

-- exact: name
SELECT ga.source_id, 4 AS match_ranking, (annotation->>'name')::text  AS matched_term
FROM CBIL.GeneAttributes ga
WHERE (annotation->>'name')::text ILIKE '%' || TRIM(searchTerm) || '%'

UNION ALL

-- or: name
SELECT ga.source_id, 5 AS match_ranking, (annotation->>'name')::text AS matched_term
FROM CBIL.GeneAttributes ga
WHERE (annotation->>'name')::text 
SIMILAR TO '%(' || replace(lower(TRIM(searchTerm)), ' or ', '|')  || ')%'

UNION ALL

SELECT ga.source_id, 3 AS match_ranking, 
'alias: ' || array_to_string(string_to_array(annotation->>'prev_symbol', '|') 
                || string_to_array(annotation->>'alias_symbol', '|'), ', ') AS matched_term
FROM CBIL.GeneAttributes ga
WHERE TRIM(searchTerm) ILIKE ANY(string_to_array(annotation->>'prev_symbol', '|') 
                        || string_to_array(annotation->>'alias_symbol', '|')))

SELECT DISTINCT gm.source_id AS primary_key,
ga.gene_symbol::text AS display,
'gene' AS record_type,
first_value(gm.match_ranking) OVER (PARTITION BY gm.source_id ORDER BY match_ranking ASC) - 2 AS match_ranking,
first_value(gm.matched_term) OVER (PARTITION BY gm.source_id ORDER BY match_ranking ASC)::text AS matched_term,
'Gene // ' || ga.gene_type || COALESCE(' // ' || (annotation->>'name')::text, '')
|| COALESCE(' // Also Known As: ' 
     || array_to_string(string_to_array(ga.annotation->>'prev_symbol', '|') 
     || string_to_array(ga.annotation->>'alias_symbol', '|'), ', '), '')
|| COALESCE(' // Location: ' || (annotation->>'location')::text,  '') AS description
FROM gene_matches gm,
CBIL.GeneAttributes ga
WHERE ga.source_id = gm.source_id
ORDER BY match_ranking ASC;

END;


$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION niagads_dataset_text_search(searchTerm TEXT) 
RETURNS TABLE ( primary_key CHARACTER VARYING,
	      	display TEXT,
		record_type TEXT,
		match_rank INTEGER,
		matched_term TEXT,
		description TEXT
	     )
AS $$
BEGIN

RETURN QUERY 

WITH st AS (SELECT TRIM(searchTerm)::text AS term),

exact_dataset_name AS (
SELECT accession, 1 AS match_ranking, NAME AS matched_term
FROM NIAGADS.DatasetAttributes, st
WHERE NAME ILIKE '%' || st.term || '%'),

exact_dataset_attribution AS (
SELECT accession, 1 AS match_ranking, attribution AS matched_term
FROM NIAGADS.DatasetAttributes, st
WHERE attribution ILIKE '%' || st.term || '%'),

dataset_matches AS (
-- partial: accession
SELECT accession, 1 AS match_ranking, accession AS matched_term
FROM NIAGADS.DatasetAttributes, st
WHERE accession LIKE st.term || '%'

UNION 

-- exact: attribution
SELECT * FROM exact_dataset_attribution

UNION 

-- exact: name
SELECT * FROM exact_dataset_name

UNION 

-- partial: name/attribution
SELECT accession, 3 AS match_ranking, COALESCE(NAME || ' (' || attribution ||  ')', NAME) AS matched_term
FROM NIAGADS.DatasetAttributes, st
WHERE COALESCE(NAME || ' (' || attribution ||  ')', NAME) SIMILAR TO '%(' || replace(st.term, ' ', '|') || ')%'
AND NOT EXISTS (SELECT * FROM exact_dataset_name)
AND NOT EXISTS (SELECT * FROM exact_dataset_attribution)

UNION

-- exact: description
SELECT accession, 5 AS match_ranking, da.description AS matched_term
FROM NIAGADS.DatasetAttributes da, st
WHERE da.description ILIKE '%' || st.term || '%'
)

SELECT DISTINCT da.accession AS primary_key,
da.accession || ': ' || COALESCE(da.name || ' (' || da.attribution ||  ')', NAME)::text AS display,
'dataset' AS record_type,
first_value(dm.match_ranking) OVER (PARTITION BY dm.accession ORDER BY dm.match_ranking ASC) -1 AS match_ranking,
first_value(dm.matched_term) OVER (PARTITION BY dm.accession ORDER BY dm.match_ranking ASC)::text AS matched_term,
'NIAGADS ACCESSION // ' || substr(da.description, 1, 130)
|| CASE WHEN LENGTH(da.description) <= 130 THEN '' ELSE '...' END AS description
FROM dataset_matches dm,
NIAGADS.DatasetAttributes da
WHERE dm.accession = da.accession
AND da.accession LIKE 'NG%'
ORDER BY match_ranking ASC;

END;


$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION gwas_dataset_text_search(searchTerm TEXT) 
RETURNS TABLE ( primary_key CHARACTER VARYING,
	      	display TEXT,
		record_type TEXT,
		match_rank INTEGER,
		matched_term TEXT,
		description TEXT
	     )
AS $$
BEGIN

RETURN QUERY 

WITH st AS (SELECT TRIM(searchTerm)::text AS term),

exact_dataset_name AS (
SELECT track, 1 AS match_ranking, NAME AS matched_term
FROM NIAGADS.TrackAttributes, st
WHERE NAME ILIKE '%' || st.term || '%'),

exact_dataset_attribution AS (
SELECT track, 1 AS match_ranking, attribution AS matched_term
FROM NIAGADS.TrackAttributes, st
WHERE attribution ILIKE '%' || st.term || '%'),

track_matches AS (
-- partial: accession
SELECT track, 1 AS match_ranking, dataset_accession AS matched_term
FROM NIAGADS.TrackAttributes, st
WHERE track LIKE st.term || '%'

UNION 

-- exact: attribution
SELECT * FROM exact_dataset_attribution

UNION 

-- exact: name
SELECT * FROM exact_dataset_name

UNION 

-- partial: name/attribution
SELECT track, 3 AS match_ranking, COALESCE(NAME || ' (' || attribution ||  ')', NAME) AS matched_term
FROM NIAGADS.TrackAttributes, st
WHERE COALESCE(NAME || ' (' || attribution ||  ')', NAME) SIMILAR TO '%(' || replace(st.term, ' ', '|') || ')%'
AND NOT EXISTS (SELECT * FROM exact_dataset_name)
AND NOT EXISTS (SELECT * FROM exact_dataset_attribution)

UNION

-- exact: description
SELECT track, 5 AS match_ranking, ta.description AS matched_term
FROM NIAGADS.TrackAttributes ta, st
WHERE ta.description ILIKE '%' || st.term || '%'
)

SELECT DISTINCT ta.track AS primary_key,
ta.dataset_accession || ': ' || COALESCE(ta.name || ' (' || ta.attribution ||  ')', NAME) AS display,
'gwas_summary' AS record_type,
first_value(tm.match_ranking) OVER (PARTITION BY tm.track ORDER BY tm.match_ranking ASC) AS match_ranking,
first_value(tm.matched_term) OVER (PARTITION BY tm.track ORDER BY tm.match_ranking ASC)::text AS matched_term,
'TRACK // ' || substr(ta.description, 1, 130)
|| CASE WHEN LENGTH(ta.description) <= 130 THEN '' ELSE '...' END AS description
FROM track_matches tm,
NIAGADS.TrackAttributes ta
WHERE tm.track = ta.track
AND ta.track LIKE 'NG%'
ORDER BY match_ranking ASC;

END;


$$ LANGUAGE plpgsql;
