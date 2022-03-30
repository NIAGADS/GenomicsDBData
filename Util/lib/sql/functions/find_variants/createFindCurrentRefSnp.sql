-- finds merged variant by tracing through merges

CREATE OR REPLACE FUNCTION find_current_ref_snp(refSnpId TEXT) 
       RETURNS TEXT AS $$
DECLARE 
	variantId TEXT;

BEGIN

	WITH RECURSIVE merges AS (	
	     SELECT ref_snp_id, merge_ref_snp_id, merge_build
	     FROM NIAGADS.MergedVariant WHERE ref_snp_id = refSnpId
	     UNION 
	     SELECT v.ref_snp_id, v.merge_ref_snp_id, v.merge_build
	     FROM NIAGADS.MergedVariant  v
	     INNER JOIN merges M ON v.ref_snp_id = m.merge_ref_snp_id 
	     ),
	     
	 Variants AS (
	     SELECT merge_ref_snp_id, merge_build FROM merges 
	     UNION ALL 
	     SELECT refSnpId AS merge_ref_snp_id, -1 AS merge_build 
	     ORDER BY merge_build DESC
	 )
	 SELECT ref_snp_id INTO variantId FROM AnnotatedVDB.Variant
	 WHERE ref_snp_id IN (SELECT merge_ref_snp_id FROM variants) LIMIT 1;

	RETURN variantId;
END;

$$ LANGUAGE plpgsql;
