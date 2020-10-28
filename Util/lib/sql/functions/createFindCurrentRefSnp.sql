-- finds merged variant by tracing through merges

CREATE OR REPLACE FUNCTION find_current_ref_snp(refSnpId TEXT) 
       RETURNS TEXT AS $$
DECLARE 
	variantId TEXT;
	build integer;
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
	SELECT ref_snp_id INTO variantId FROM (
	SELECT v.merge_ref_snp_id AS ref_snp_id, v.merge_build 
	FROM merges r, NIAGADS.MergedVariant v
	WHERE (v.ref_snp_id = r.variant OR v.merge_ref_snp_id = r.variant)
	UNION ALL
	SELECT ref_snp_id, (vep_output->'input'->'info'->'dbSNPBuildID')::integer AS merge_build FROM 
	AnnotatedVDB.Variant WHERE ref_snp_id = refSnpId
	ORDER BY merge_build DESC LIMIT 1) a;

	RETURN variantId;
END;

$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION find_current_ref_snp(refSnpId TEXT, chrom TEXT) 
       RETURNS TEXT AS $$
DECLARE 
	variantId TEXT;
	build integer;
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
	SELECT ref_snp_id INTO variantId FROM (
	SELECT v.merge_ref_snp_id AS ref_snp_id, v.merge_build 
	FROM merges r, NIAGADS.MergedVariant v
	WHERE (v.ref_snp_id = r.variant OR v.merge_ref_snp_id = r.variant)
	UNION ALL
	SELECT ref_snp_id, (vep_output->'input'->'info'->'dbSNPBuildID')::integer AS merge_build FROM 
	AnnotatedVDB.Variant WHERE ref_snp_id = refSnpId AND chromosome = chrom
	ORDER BY merge_build DESC LIMIT 1) a;

	RETURN variantId;
END;





$$ LANGUAGE plpgsql;
