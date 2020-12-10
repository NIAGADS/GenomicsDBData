-- finds variant by chr:pos:ref:alt id

CREATE OR REPLACE FUNCTION find_variant_primary_key(variantID TEXT)
       RETURNS TEXT AS $$
DECLARE
	recordPK TEXT;
BEGIN

WITH MatchedVariants AS (
SELECT CASE 
 WHEN LOWER(variantID) LIKE 'rs%' AND LOWER(variantID) NOT LIKE '%:%' THEN 
        (SELECT record_primary_key FROM find_variant_by_refsnp(LOWER(variantID), TRUE))
 WHEN LOWER(variantID) LIKE '%:%' AND LOWER(variantID) NOT LIKE '%_rs%' THEN
        (SELECT record_primary_key AS source_id FROM find_variant_by_metaseq_id_variations(variantID, TRUE))
 WHEN LOWER(variantID) LIKE '%_rs%' AND LOWER(variantID) LIKE '%:%' THEN
        (SELECT v.record_primary_key FROM AnnotatedVDB.Variant v
          WHERE LEFT(metaseq_id, 50) = LEFT(split_part(variantID, '_', 1), 50) 
	  AND metaseq_id = split_part(variantID, '_', 1) 
	  AND ref_snp_id = split_part(variantID, '_', 2)
	  AND chromosome = 'chr' || split_part(variantID, ':', 1)) END AS variant_primary_key)
--SELECT CASE WHEN variant_primary_key IS NULL THEN variantID
--ELSE variant_primary_key END INTO recordPK 
SELECT variant_primary_key INTO recordPK -- need to be able to track no matches
FROM MatchedVariants;

RETURN recordPK;

END;

$$ LANGUAGE plpgsql;

