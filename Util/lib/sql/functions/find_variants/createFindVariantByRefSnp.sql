-- finds merged variant by tracing through merges

--variantId = rsX:ref:alt
DROP FUNCTION find_variant_by_refsnp_and_alleles(text, boolean) ;
CREATE OR REPLACE FUNCTION find_variant_by_refsnp_and_alleles(variantId TEXT, firstHitOnly BOOLEAN DEFAULT FALSE)
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT, alleles TEXT, variant_class TEXT,
       	             is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB) AS $$
BEGIN
	RETURN QUERY
	WITH Lookup AS (SELECT LOWER(split_part(variantID, ':', 1)) AS ref_snp_id,
	split_part(variantID, ':', 2) AS refA, split_part(variantID, ':',3) AS altA),
	
	ValidLookup AS (SELECT find_current_ref_snp(l.ref_snp_id) AS ref_snp_id,
	CASE WHEN l.refA = '' THEN 'N' ELSE l.refA END AS refA,
	CASE WHEN l.altA = '' THEN 'N' ELSE l.altA END AS altA FROM Lookup l),

	RefSnpMatch AS (SELECT * FROM find_variant_by_refsnp((SELECT l.ref_snp_id FROM ValidLookup l))),

 	AlleleMatch AS (
	SELECT v.record_primary_key::TEXT, v.ref_snp_id, v.metaseq_id,
 	v.display_attributes->>'display_allele' AS alleles,
	v.display_attributes->>'variant_class_abbrev' AS variant_class,
	CASE WHEN v.is_adsp_variant THEN TRUE ELSE FALSE END AS is_adsp_variant, v.bin_index,
	jsonb_build_object(
	 'associations', v.gwas_flags,
     'allele_frequencies', v.allele_frequencies,
     'cadd_scores', v.cadd_scores,
	 'most_severe_consequence', v.adsp_most_severe_consequence,
	 'ranked_consequences', v.adsp_ranked_consequences,	 
	 'ADSP_QC', v.adsp_qc #- '{17k,info,AF}' #- '{17k,info,AC}' #- '{17k,info,AN}',
	 'mapped_coordinates', COALESCE(v.other_annotation->'GRCh37' || '{"assembly":"GRCh37"}', v.other_annotation->'GRCh38' || '{"assembly":"GRCh38"}')) AS annotation
	FROM AnnotatedVDB.Variant v, ValidLookup l
 	WHERE v.ref_snp_id = l.ref_snp_id
 	AND array_sort(ARRAY[split_part(v.metaseq_id, ':', 3), split_part(v.metaseq_id, ':', 4)]) @>
	CASE WHEN l.refA = 'N' THEN ARRAY[l.altA] 
	WHEN l.altA = 'N'  THEN ARRAY[l.refA]
	ELSE array_sort(ARRAY[l.refA, l.altA]) END)

	SELECT r.record_primary_key, r.ref_snp_id, r.metaseq_id
	, r.alleles, r.variant_class
	, r.is_adsp_variant, r.bin_index
	, r.annotation || '{"allele_match": false}'::jsonb AS annotation FROM RefSnpMatch r WHERE NOT EXISTS (SELECT * FROM AlleleMatch)
	UNION ALL
	SELECT r.record_primary_key, r.ref_snp_id, r.metaseq_id
	, r.alleles, r.variant_class
	, r.is_adsp_variant, r.bin_index
	, r.annotation || '{"allele_match": true}'::jsonb AS annotation  FROM AlleleMatch r
	LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;


DROP FUNCTION IF EXISTS find_variant_by_refsnp(refSnpId TEXT, firstHitOnly BOOLEAN);
CREATE OR REPLACE FUNCTION find_variant_by_refsnp(refSnpId TEXT, firstHitOnly BOOLEAN DEFAULT FALSE)
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT, alleles TEXT, variant_class TEXT,
       	             is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB) AS $$

BEGIN
	RETURN QUERY
	WITH searchTerm AS (SELECT find_current_ref_snp(refSnpID) AS ref_snp_id)
	SELECT v.record_primary_key::TEXT, v.ref_snp_id, v.metaseq_id,
 	v.display_attributes->>'display_allele' AS alleles,
	v.display_attributes->>'variant_class_abbrev' AS variant_class,
	CASE WHEN v.is_adsp_variant THEN TRUE ELSE FALSE END AS is_adsp_variant, v.bin_index,
	jsonb_build_object(
	 'associations', v.gwas_flags,
     'allele_frequencies', v.allele_frequencies,
     'cadd_scores', v.cadd_scores,
	 'most_severe_consequence', v.adsp_most_severe_consequence,
	 'ranked_consequences', v.adsp_ranked_consequences,	 
	 'ADSP_QC', v.adsp_qc #- '{17k,info,AF}' #- '{17k,info,AC}' #- '{17k,info,AN}',
	 'mapped_coordinates', COALESCE(v.other_annotation->'GRCh37' || '{"assembly":"GRCh37"}', v.other_annotation->'GRCh38' || '{"assembly":"GRCh38"}')) AS annotation
	FROM AnnotatedVDB.Variant v, searchTerm
 	WHERE v.ref_snp_id = searchTerm.ref_snp_id
	LIMIT CASE WHEN firstHitOnly THEN 1 END;

END;

$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS find_variant_by_refsnp(refSnpId TEXT, chrm TEXT, firstHitOnly BOOLEAN);
CREATE OR REPLACE FUNCTION find_variant_by_refsnp(refSnpId TEXT, chrm TEXT, firstHitOnly BOOLEAN DEFAULT FALSE)
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT, alleles TEXT, variant_class TEXT,
       	             is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB) AS $$

BEGIN
	RETURN QUERY
	WITH searchTerm AS (SELECT find_current_ref_snp(refSnpID, chrm) AS ref_snp_id)
	SELECT v.record_primary_key::TEXT, v.ref_snp_id, v.metaseq_id,
	 v.display_attributes->>'display_allele' AS alleles,
	v.display_attributes->>'variant_class_abbrev' AS variant_class,
	CASE WHEN v.is_adsp_variant THEN TRUE ELSE FALSE END AS is_adsp_variant, v.bin_index,
	jsonb_build_object(
	 'associations', v.gwas_flags,
     'allele_frequencies', v.allele_frequencies,
     'cadd_scores', v.cadd_scores,
	 'most_severe_consequence', v.adsp_most_severe_consequence,
	 'ranked_consequences', v.adsp_ranked_consequences,	 
	 'ADSP_QC', v.adsp_qc #- '{17k,info,AF}' #- '{17k,info,AC}' #- '{17k,info,AN}',
	 'mapped_coordinates', COALESCE(v.other_annotation->'GRCh37' || '{"assembly":"GRCh37"}', v.other_annotation->'GRCh38' || '{"assembly":"GRCh38"}')) AS annotation
	FROM AnnotatedVDB.Variant v, searchTerm
 	WHERE v.ref_snp_id = searchTerm.ref_snp_id
	AND v.chromosome = chrm
	LIMIT CASE WHEN firstHitOnly THEN 1 END;

END;

$$ LANGUAGE plpgsql;

--DROP FUNCTION IF EXISTS get_variant_annotation_by_refsnp(text,text,boolean) ;

CREATE OR REPLACE FUNCTION get_variant_annotation_by_refsnp(refSnpId TEXT, chrm TEXT, firstHitOnly BOOLEAN DEFAULT FALSE) 
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
       	             has_genomicsdb_annotation BOOLEAN, is_adsp_variant BOOLEAN, bin_index LTREE, 
		     adsp_most_severe_consequence JSONB, cadd_scores JSONB, allele_frequencies JSONB) AS $$
BEGIN
	RETURN QUERY
	WITH searchTerm AS (SELECT find_current_ref_snp(refSnpID, chrm) AS ref_snp_id)
	SELECT v.record_primary_key::TEXT, v.ref_snp_id, v.metaseq_id,
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
	SELECT v.record_primary_key::TEXT, v.ref_snp_id, v.metaseq_id,
	v.has_genomicsdb_annotation, v.is_adsp_variant, v.bin_index,
	v.adsp_most_severe_consequence, v.cadd_scores, v.allele_frequencies 
	FROM AnnotatedVDB.Variant v, searchTerm
 	WHERE v.ref_snp_id = searchTerm.ref_snp_id
	LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;
