-- finds merged variant by tracing through merges

DROP FUNCTION find_variant_by_refsnp_and_alleles;

--variantId = rsX:ref:alt
CREATE OR REPLACE FUNCTION find_variant_by_refsnp_and_alleles(variantId TEXT) 
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
       	             is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB) AS $$
BEGIN
	RETURN QUERY
	WITH Lookup AS (SELECT LOWER(split_part(variantID, ':', 1)) AS ref_snp_id,
	split_part(variantID, ':', 2) AS refA, split_part(variantID, ':',3) AS altA),
	
	ValidLookup AS (SELECT find_current_ref_snp(l.ref_snp_id) AS ref_snp_id, l.refA, l.altA FROM Lookup l)
	
	SELECT v.record_primary_key, v.ref_snp_id, v.metaseq_id, v.is_adsp_variant, v.bin_index,
	jsonb_build_object(
	 'GenomicsDB', v.other_annotation->'GenomicsDB',
	 'mapped_coordinates', COALESCE(v.other_annotation->'GRCh37' || '{"assembly":"GRCh37"}', v.other_annotation->'GRCh38' || '{"assembly":"GRCh38"}')) AS annotation
	FROM AnnotatedVDB.Variant v, ValidLookup l
 	WHERE v.ref_snp_id = l.ref_snp_id
	AND array_sort(ARRAY[split_part(v.metaseq_id, ':', 3), split_part(v.metaseq_id, ':', 4)]) @> 
	CASE WHEN l.refA IS NULL THEN ARRAY[l.altA] ELSE array_sort(ARRAY[l.refA, l.altA]) END;
END;

$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION find_variant_by_refsnp(refSnpId TEXT, firstHitOnly BOOLEAN DEFAULT FALSE)
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
       	             is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB) AS $$

BEGIN
	RETURN QUERY
	WITH searchTerm AS (SELECT find_current_ref_snp(refSnpID) AS ref_snp_id)
	SELECT v.record_primary_key, v.ref_snp_id, v.metaseq_id, v.is_adsp_variant, v.bin_index,
	jsonb_build_object(
	 'GenomicsDB', v.other_annotation->'GenomicsDB',
	 'mapped_coordinates', COALESCE(v.other_annotation->'GRCh37' || '{"assembly":"GRCh37"}', v.other_annotation->'GRCh38' || '{"assembly":"GRCh38"}')) AS annotation
	FROM AnnotatedVDB.Variant v, searchTerm
 	WHERE v.ref_snp_id = searchTerm.ref_snp_id
	LIMIT CASE WHEN firstHitOnly THEN 1 END;

END;

$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION find_variant_by_refsnp(refSnpId TEXT, chrm TEXT, firstHitOnly BOOLEAN DEFAULT FALSE)
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
       	             is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB) AS $$

BEGIN
	RETURN QUERY
	WITH searchTerm AS (SELECT find_current_ref_snp(refSnpID, chrm) AS ref_snp_id)
	SELECT v.record_primary_key, v.ref_snp_id, v.metaseq_id, v.is_adsp_variant, v.bin_index,
	jsonb_build_object(
	 'GenomicsDB', v.other_annotation->'GenomicsDB',
	 'mapped_coordinates', COALESCE(v.other_annotation->'GRCh37' || '{"assembly":"GRCh37"}', v.other_annotation->'GRCh38' || '{"assembly":"GRCh38"}')) AS annotation
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
