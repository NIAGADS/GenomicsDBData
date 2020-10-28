-- site search  -- one function for each record type

CREATE OR REPLACE FUNCTION variant_text_search(searchTerm TEXT) 
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

SELECT v.record_pk AS primary_key,
CASE WHEN v.source_id IS NOT NULL THEN v.source_id
WHEN LENGTH(split_part(v.record_pk, '_', 1)) > 30 THEN substr(split_part(v.record_pk, '_', 1), 0, 27) ELSE split_part(v.record_pk, '_', 1) END AS display,
'variant' AS record_type,
1 AS match_ranking,
CASE WHEN mv.term LIKE 'rs%' AND v.source_id != mv.term THEN 'merged from: ' || mv.term ELSE replace(mv.term, '_', ':') END AS matched_term,
CASE WHEN v.is_adsp_variant THEN ' ADSP VARIANT' ELSE 'VARIANT' END
|| ' // ' || variant_class_abbrev
|| ' // Alleles: ' || display_allele
|| COALESCE(' // ' || v.most_severe_consequence, '')
|| COALESCE(' // ' || (v.annotation->'VEP_MS_CONSEQUENCE'->>'impact')::text, '') AS description
FROM NIAGADS.Variant v,
(SELECT TRIM(searchTerm) AS term, find_variant_primary_key(TRIM(searchTerm)) AS record_pk) mv
WHERE v.record_pk = mv.record_pk

UNION ALL

SELECT v.record_pk AS primary_key,
CASE WHEN v.source_id IS NOT NULL THEN v.source_id
WHEN LENGTH(split_part(v.record_pk, '_', 1)) > 30 THEN substr(split_part(v.record_pk, '_', 1), 0, 27) ELSE split_part(v.record_pk, '_', 1) END AS display,
'variant' AS record_type,
2 AS match_ranking,
CASE WHEN TRIM(searchTerm) LIKE 'rs%' AND v.source_id != TRIM(searchTerm) THEN 'merged from: ' || TRIM(searchTerm) ELSE TRIM(searchTerm) END  AS matched_term,
CASE WHEN v.is_adsp_variant THEN ' ADSP VARIANT' ELSE 'VARIANT' END
|| ' // ' || variant_class_abbrev
|| ' // Alleles: ' || display_allele
|| COALESCE(' // ' || v.most_severe_consequence, '')
|| COALESCE(' // ' || (v.annotation->'VEP_MS_CONSEQUENCE'->>'impact')::text, '') AS description
FROM NIAGADS.Variant v
WHERE (TRIM(searchTerm) ~ '^[0-9]' AND TRIM(searchTerm) LIKE '%:%' AND array_length(regexp_split_to_array(TRIM(searchTerm), ':'),1) = 2) AND (v.chromosome = 'chr' || split_part(TRIM(searchTerm), ':', 1)
AND v.position = split_part(TRIM(searchTerm), ':', 2)::integer AND v.has_annotation)
OR (TRIM(searchTerm) ~ '^[0-9]' AND TRIM(searchTerm) LIKE '%:%' AND array_length(regexp_split_to_array(TRIM(searchTerm), ':'),1) = 3) AND (v.chromosome = 'chr' || split_part(TRIM(searchTerm), ':', 1)
AND v.position = split_part(TRIM(searchTerm), ':', 2)::integer AND (v.ref_allele = split_part(TRIM(searchTerm), ':', 3)  OR v.alt_allele = split_part(TRIM(searchTerm), ':', 3)) AND v.has_annotation)

ORDER BY match_ranking ASC;

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
SELECT ga.source_id,  1 AS match_ranking, ga.gene_symbol AS matched_term
FROM CBIL.GeneAttributes ga
WHERE ga.gene_symbol ILIKE TRIM(searchTerm) 

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
