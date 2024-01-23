/* NOTE THESE FUNCTIONS ARE DERIVED FROM THOSE IN ../website_search/createFindVariantPrimaryKey.sql; may need to adjust accordingly */

CREATE OR REPLACE FUNCTION map_variants(variantID TEXT, firstHitOnly BOOLEAN DEFAULT TRUE) 
       RETURNS TABLE(search_term TEXT, mapping JSONB) AS $$

BEGIN
RETURN QUERY

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
    FROM find_variant_by_metaseq_id_variations(variant.id, firstHitOnly))
WHEN LOWER(variant.id) LIKE '%:rs%' AND LOWER(variant.id) LIKE '%:%' THEN
    (SELECT jsonb_agg(jsonb_build_object('primary_key', av.record_primary_key, 'bin_index', av.bin_index)) 
    FROM AnnotatedVDB.Variant av, variant WHERE record_primary_key = variant.id) 
END AS mapped_variant
FROM variant GROUP BY variant.id
)

SELECT mv.search_term, mv.mapped_variant 
FROM MatchedVariants mv;

END;