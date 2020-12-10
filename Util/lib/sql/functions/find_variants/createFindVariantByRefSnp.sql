-- finds merged variant by tracing through merges

CREATE OR REPLACE FUNCTION find_variant_by_refsnp_and_alleles(refSnpId TEXT, refA TEXT, altA TEXT) 
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
       	             has_genomicsdb_annotation BOOLEAN, is_adsp_variant BOOLEAN, bin_index LTREE) AS $$
BEGIN
	RETURN QUERY
	WITH searchTerm AS (SELECT find_current_ref_snp(refSnpID) AS ref_snp_id)
	SELECT v.record_primary_key, v.ref_snp_id, v.metaseq_id, v.has_genomicsdb_annotation,
	       v.is_adsp_variant, v.bin_index
	FROM AnnotatedVDB.Variant v, searchTerm
 	WHERE v.ref_snp_id = searchTerm.ref_snp_id
	AND array_sort(ARRAY[split_part(v.metaseq_id, ':', 3), split_part(v.metaseq_id, ':', 4)]) @> 
	CASE WHEN refA IS NULL THEN ARRAY[altA] ELSE array_sort(ARRAY[refA, altA]) END;
END;

$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION find_variant_by_refsnp(refSnpId TEXT, firstHitOnly BOOLEAN DEFAULT FALSE) 
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
       	             has_genomicsdb_annotation BOOLEAN, is_adsp_variant BOOLEAN, bin_index LTREE) AS $$
BEGIN
	RETURN QUERY
	WITH searchTerm AS (SELECT find_current_ref_snp(refSnpID) AS ref_snp_id)
	SELECT v.record_primary_key, v.ref_snp_id, v.metaseq_id, v.has_genomicsdb_annotation,
	       v.is_adsp_variant, v.bin_index
	FROM AnnotatedVDB.Variant v, searchTerm
 	WHERE v.ref_snp_id = searchTerm.ref_snp_id
	LIMIT CASE WHEN firstHitOnly THEN 1 END;

END;

$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION find_variant_by_refsnp(refSnpId TEXT, chrm TEXT, firstHitOnly BOOLEAN DEFAULT FALSE) 
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
       	             has_genomicsdb_annotation BOOLEAN, is_adsp_variant BOOLEAN, bin_index LTREE) AS $$
BEGIN
	RETURN QUERY
	WITH searchTerm AS (SELECT find_current_ref_snp(refSnpID, chrm) AS ref_snp_id)
	SELECT v.record_primary_key, v.ref_snp_id, v.metaseq_id,
	v.has_genomicsdb_annotation, v.is_adsp_variant, v.bin_index
	FROM AnnotatedVDB.Variant v, searchTerm
 	WHERE v.ref_snp_id = searchTerm.ref_snp_id
	AND v.chromosome = chrm
	LIMIT CASE WHEN firstHitOnly THEN 1 END;

END;

$$ LANGUAGE plpgsql;

--DROP FUNCTION get_variant_annotation_by_refsnp(text,text,boolean) ;

CREATE OR REPLACE FUNCTION get_variant_annotation_by_refsnp(refSnpId TEXT, chrm TEXT, firstHitOnly BOOLEAN DEFAULT FALSE) 
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
       	             has_genomicsdb_annotation BOOLEAN, is_adsp_variant BOOLEAN, bin_index LTREE, 
		     adsp_most_severe_consequence JSONB, cadd_scores JSONB, allele_frequencies JSONB) AS $$
BEGIN
	RETURN QUERY
	WITH searchTerm AS (SELECT find_current_ref_snp(refSnpID, chrm) AS ref_snp_id)
	SELECT v.record_primary_key, v.ref_snp_id, v.metaseq_id,
	v.has_genomicsdb_annotation, v.is_adsp_variant, v.bin_index,
	v.adsp_most_severe_consequence, v.cadd_scores, v.allele_frequencies 
	FROM AnnotatedVDB.Variant v, searchTerm
 	WHERE v.ref_snp_id = searchTerm.ref_snp_id
	AND v.chromosome = chrm
	LIMIT CASE WHEN firstHitOnly THEN 1 END;

END;

$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_variant_annotation_by_refsnp(refSnpId TEXT, firstHitOnly BOOLEAN DEFAULT FALSE) 
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
       	             has_genomicsdb_annotation BOOLEAN, is_adsp_variant BOOLEAN, bin_index LTREE, 
		     adsp_most_severe_consequence JSONB, cadd_scores JSONB, allele_frequencies JSONB) AS $$
BEGIN
	RETURN QUERY
	WITH searchTerm AS (SELECT find_current_ref_snp(refSnpID) AS ref_snp_id)
	SELECT v.record_primary_key, v.ref_snp_id, v.metaseq_id,
	v.has_genomicsdb_annotation, v.is_adsp_variant, v.bin_index,
	v.adsp_most_severe_consequence, v.cadd_scores, v.allele_frequencies 
	FROM AnnotatedVDB.Variant v, searchTerm
 	WHERE v.ref_snp_id = searchTerm.ref_snp_id
	LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;
