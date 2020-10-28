-- finds merged variant by tracing through merges

CREATE OR REPLACE FUNCTION find_merged_variant_id(refSnpId TEXT) 
       RETURNS INTEGER AS $$
DECLARE 
	variantId INTEGER;
BEGIN
	WITH merges AS (
	SELECT ref_snp_id AS variant 
	FROM NIAGADS.MergedVariant 
	WHERE merge_ref_snp_id = refSnpId
	UNION	
	SELECT merge_ref_snp_id variant 
	FROM NIAGADS.MergedVariant 
	WHERE ref_snp_id = refSnpId
	UNION SELECT refSnpId AS variant)
	SELECT v.merge_variant_id INTO variantId 
	FROM merges r, NIAGADS.MergedVariant v
	WHERE (v.ref_snp_id = r.variant OR v.merge_ref_snp_id = r.variant)
	AND v.merge_variant_id IS NOT NULL LIMIT 1;

	RETURN variantId;
END;



$$ LANGUAGE plpgsql;
