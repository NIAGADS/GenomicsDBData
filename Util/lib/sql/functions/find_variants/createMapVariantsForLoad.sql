/* NOTE THESE FUNCTIONS ARE DERIVED FROM THOSE IN ../website_search/createFindVariantPrimaryKey.sql; may need to adjust accordingly */

--DROP FUNCTION map_variants(TEXT, BOOLEAN,  BOOLEAN, BOOLEAN);
CREATE OR REPLACE FUNCTION map_variants(variantID TEXT, firstHitOnly BOOLEAN DEFAULT TRUE, 
    checkAltAlleles BOOLEAN DEFAULT TRUE, checkNormalizedAlleles BOOLEAN DEFAULT FALSE) 
       RETURNS JSONB AS $$
DECLARE 
	result JSONB;
BEGIN

WITH variant AS (SELECT regexp_split_to_table(variantID, ',') AS id),

MatchedVariants AS (
    SELECT variant.id AS search_term,
    CASE WHEN LOWER(variant.id) LIKE 'rs%' AND LOWER(variant.id) NOT LIKE '%:%' THEN 
        (SELECT jsonb_agg(jsonb_build_object('primary_key', record_primary_key, 'bin_index', bin_index) ) 
        FROM find_variant_by_refsnp(LOWER(variant.id), firstHitOnly))
    WHEN LOWER(variant.id) LIKE 'rs%' AND LOWER(variant.id) LIKE '%:%' THEN -- refsnp & alleles
        (SELECT jsonb_agg(jsonb_build_object('primary_key', record_primary_key, 'bin_index', bin_index) ) 
        FROM find_variant_by_refsnp_and_alleles(variant.id, firstHitOnly))
    WHEN LOWER(variant.id) LIKE '%:%' AND LOWER(variant.id) NOT LIKE '%:rs%' THEN
        (SELECT jsonb_agg(jsonb_build_object('primary_key', record_primary_key, 'bin_index', bin_index) ) 
        FROM find_variant_by_metaseq_id_variations(variant.id, firstHitOnly, checkAltAlleles, checkNormalizedAlleles))
    WHEN LOWER(variant.id) LIKE '%:rs%' AND LOWER(variant.id) LIKE '%:%' THEN
        (SELECT jsonb_agg(jsonb_build_object('primary_key', av.record_primary_key, 'bin_index', av.bin_index)) 
        FROM AnnotatedVDB.Variant av, variant WHERE record_primary_key = variant.id) 
    END as match
FROM variant GROUP BY variant.id
)

SELECT jsonb_object_agg(mv.search_term, mv.match) INTO result
FROM MatchedVariants mv;

RETURN result;
END;

$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION map_variants_normalized_check_only(variantID TEXT, firstHitOnly BOOLEAN DEFAULT TRUE, 
    checkAltAlleles BOOLEAN DEFAULT TRUE) 
       RETURNS JSONB AS $$
DECLARE 
	result JSONB;
BEGIN

WITH variant AS (SELECT regexp_split_to_table(variantID, ',') AS id),

MatchedVariants AS (
    SELECT variant.id AS search_term,
    (SELECT jsonb_agg(jsonb_build_object('primary_key', record_primary_key, 'bin_index', bin_index) ) 
        FROM find_variant_by_metaseq_id_normalized_variations(variant.id, firstHitOnly, checkAltAlleles)) as match    
FROM variant GROUP BY variant.id
)

SELECT jsonb_object_agg(mv.search_term, mv.match) INTO result
FROM MatchedVariants mv;

RETURN result;
END;

$$ LANGUAGE plpgsql;