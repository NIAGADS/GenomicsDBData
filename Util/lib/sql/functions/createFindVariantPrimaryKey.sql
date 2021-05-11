-- finds variant by chr:pos:ref:alt id

CREATE OR REPLACE FUNCTION find_variant_primary_key(variantID TEXT)
       RETURNS TEXT AS $$
DECLARE
	recordPK TEXT;
BEGIN

WITH
MatchedVariants AS (
SELECT CASE 
 WHEN LOWER(variantID) LIKE 'rs%' AND LOWER(variantID) NOT LIKE '%:%' THEN 
        (SELECT record_primary_key FROM find_variant_by_refsnp(LOWER(variantID), TRUE))
 WHEN LOWER(variantID) LIKE '%:%' AND LOWER(variantID) NOT LIKE '%_rs%' THEN
        (SELECT record_primary_key AS source_id FROM find_variant_by_metaseq_id_variations(variantID, TRUE))
 WHEN LOWER(variantID) LIKE '%_rs%' AND LOWER(variantID) LIKE '%:%' THEN
        variantID -- assume since it is in our format (chr:pos:ref:alt_refsnp), it is a valid NIAGADS GenomicsDB variant id
 END AS variant_primary_key
)
--SELECT CASE WHEN variant_primary_key IS NULL THEN variantID
--ELSE variant_primary_key END INTO recordPK 
SELECT variant_primary_key INTO recordPK -- need to be able to track no matches
FROM MatchedVariants;

RETURN recordPK;

END;

$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_variant_primary_keys(variantID TEXT)
       RETURNS TABLE(search_term TEXT, variant_primary_key TEXT) AS $$
--DECLARE
	--recordPK TEXT;
BEGIN
RETURN QUERY
WITH variant AS (SELECT regexp_split_to_table(variantID, ',') AS id),

MatchedVariants AS (
SELECT variant.id AS search_term,
CASE 
 WHEN LOWER(variant.id) LIKE 'rs%' AND LOWER(variant.id) NOT LIKE '%:%' THEN 
        (SELECT record_primary_key FROM find_variant_by_refsnp(LOWER(variant.id), TRUE))
 WHEN LOWER(variant.id) LIKE '%:%' AND LOWER(variant.id) NOT LIKE '%_rs%' THEN
        (SELECT record_primary_key AS source_id FROM find_variant_by_metaseq_id_variations(variant.id, TRUE))
 WHEN LOWER(variant.id) LIKE '%_rs%' AND LOWER(variant.id) LIKE '%:%' THEN
        variant.id -- assume since it is in our format (chr:pos:ref:alt_refsnp), it is a valid NIAGADS GenomicsDB variant id
 END AS variant_primary_key
FROM variant
)
--SELECT CASE WHEN variant_primary_key IS NULL THEN variant.id
--ELSE variant_primary_key END INTO recordPK 
SELECT mv.search_term, mv.variant_primary_key --INTO recordPK -- need to be able to track no matches
FROM MatchedVariants mv;

END;

$$ LANGUAGE plpgsql;

