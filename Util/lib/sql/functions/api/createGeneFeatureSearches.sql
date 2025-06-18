
--DROP FUNCTION gene_location_lookup(searchTerm TEXT);
CREATE OR REPLACE FUNCTION gene_location_lookup(searchTerm TEXT) 
       RETURNS TEXT AS $$
DECLARE 
	featureSpan TEXT;
BEGIN
        WITH gene_matches AS (
        -- exact: source_id
        SELECT ga.source_id, 1 AS match_ranking, ga.source_id AS matched_term
        FROM CBIL.GeneAttributes ga
        WHERE ga.source_id ILIKE searchTerm

        UNION ALL

        -- exact: gene_symbol
        SELECT ga.source_id, 1 AS match_ranking, ga.gene_symbol AS matched_term
        FROM CBIL.GeneAttributes ga
        WHERE ga.gene_symbol ILIKE searchTerm

        UNION ALL

        -- exact: entrez_id
        SELECT ga.source_id, 1 AS match_ranking, (annotation->>'entrez_id')::text AS matched_term
        FROM CBIL.GeneAttributes ga
        WHERE (annotation->>'entrez_id')::text = searchTerm

        UNION ALL

        -- aliases
        SELECT ga.source_id, 3 AS match_ranking, 
        'alias: ' || array_to_string(string_to_array(annotation->>'prev_symbol', '|') 
                        || string_to_array(annotation->>'alias_symbol', '|'), ', ') AS matched_term
        FROM CBIL.GeneAttributes ga
        WHERE searchTerm ILIKE ANY(string_to_array(annotation->>'prev_symbol', '|') 
                                || string_to_array(annotation->>'alias_symbol', '|'))

        ),

        ranked_matches AS (
        SELECT DISTINCT gm.source_id AS primary_key,
        first_value(gm.match_ranking) OVER (PARTITION BY gm.source_id ORDER BY match_ranking ASC) - 2 AS match_ranking,
        first_value(gm.matched_term) OVER (PARTITION BY gm.source_id ORDER BY match_ranking ASC)::text AS matched_term,
        ga.chromosome || ':' || ga.location_start || '-' || ga.location_end AS span
        FROM gene_matches gm,
        CBIL.GeneAttributes ga
        WHERE ga.source_id = gm.source_id
        ORDER BY match_ranking)

        SELECT span into featureSpan FROM ranked_matches LIMIT 1;

        RETURN featureSpan;
    END;

$$ LANGUAGE plpgsql;


--DROP FUNCTION gene_lookup(searchTerm TEXT);
CREATE OR REPLACE FUNCTION gene_lookup(searchTerm TEXT) 
       RETURNS TEXT AS $$
DECLARE 
	pk TEXT;
BEGIN
        WITH gene_matches AS (
        -- exact: source_id
        SELECT ga.source_id, 1 AS match_ranking, ga.source_id AS matched_term
        FROM CBIL.GeneAttributes ga
        WHERE ga.source_id ILIKE searchTerm

        UNION ALL

        -- exact: gene_symbol
        SELECT ga.source_id, 1 AS match_ranking, ga.gene_symbol AS matched_term
        FROM CBIL.GeneAttributes ga
        WHERE ga.gene_symbol ILIKE searchTerm

        UNION ALL

        -- exact: entrez_id
        SELECT ga.source_id, 1 AS match_ranking, (annotation->>'entrez_id')::text AS matched_term
        FROM CBIL.GeneAttributes ga
        WHERE (annotation->>'entrez_id')::text = searchTerm

        UNION ALL

        -- aliases
        SELECT ga.source_id, 3 AS match_ranking, 
        'alias: ' || array_to_string(string_to_array(annotation->>'prev_symbol', '|') 
                        || string_to_array(annotation->>'alias_symbol', '|'), ', ') AS matched_term
        FROM CBIL.GeneAttributes ga
        WHERE searchTerm ILIKE ANY(string_to_array(annotation->>'prev_symbol', '|') 
                                || string_to_array(annotation->>'alias_symbol', '|'))

        ),

        ranked_matches AS (
        SELECT DISTINCT gm.source_id AS primary_key,
        first_value(gm.match_ranking) OVER (PARTITION BY gm.source_id ORDER BY match_ranking ASC) - 2 AS match_ranking,
        first_value(gm.matched_term) OVER (PARTITION BY gm.source_id ORDER BY match_ranking ASC)::text AS matched_term,
        ga.chromosome || ':' || ga.location_start || '-' || ga.location_end AS span
        FROM gene_matches gm,
        CBIL.GeneAttributes ga
        WHERE ga.source_id = gm.source_id
        ORDER BY match_ranking)

        SELECT primary_key into pk FROM ranked_matches LIMIT 1;

        RETURN pk;
    END;

$$ LANGUAGE plpgsql;