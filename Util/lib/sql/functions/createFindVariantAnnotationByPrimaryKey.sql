CREATE OR REPLACE FUNCTION get_variant_annotation_by_primary_key(variantPK TEXT)
       RETURNS TABLE(record_primary_key TEXT,
       adsp_most_severe_consequence JSONB, cadd_scores JSONB, allele_frequencies JSONB) AS $$

DECLARE metaseqId TEXT;
DECLARE refSnpId TEXT;
DECLARE chrm TEXT;
BEGIN
	
	SELECT split_part(variantPK, '_', 1) INTO metaseqId;
	SELECT split_part(variantPK, '_', 2) INTO refSnpId;
	SELECT 'chr' || split_part(variantPK, ':', 1)::text INTO chrm;

	RETURN QUERY

	SELECT variantPK AS variant_primary_key, 
	v.adsp_most_severe_consequence, 
	v.cadd_scores, 
	v.allele_frequencies 
	FROM AnnotatedVDB.Variant v
	WHERE LEFT(v.metaseq_id, 50) = LEFT(metaseqId, 50)
	AND v.metaseq_id = metaseqId
	AND CASE WHEN LENGTH(refSnpId) = 0 THEN TRUE
	ELSE v.ref_snp_id = refSnpId END 
	AND v.chromosome = chrm;
END;

$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_adsp_qc_by_primary_key(variantPK TEXT)
       RETURNS TABLE(record_primary_key TEXT, adsp_qc JSONB) AS $$


DECLARE metaseqId TEXT;
DECLARE refSnpId TEXT;
DECLARE chrm TEXT;
BEGIN
	
	SELECT split_part(variantPK, '_', 1) INTO metaseqId;
	SELECT split_part(variantPK, '_', 2) INTO refSnpId;
	SELECT 'chr' || split_part(variantPK, ':', 1)::text INTO chrm;

	RETURN QUERY

	SELECT variantPK AS variant_primary_key, 
	COALESCE(CASE WHEN v.other_annotation->'ADSP_WES' IS NOT NULL THEN 
	jsonb_build_object('ADSP_WES', 
	jsonb_build_object('FILTER', v.other_annotation->'ADSP_WES'->>'FILTER', 
			   'FILTER_STATUS', v.other_annotation->'ADSP_WES'->>'FILTER_STATUS'))
	ELSE NULL END, '{}') || 
	COALESCE(CASE WHEN v.other_annotation->'ADSP_WGS' IS NOT NULL THEN
	jsonb_build_object('ADSP_WGS',
	jsonb_build_object('FILTER', v.other_annotation->'ADSP_WGS'->>'FILTER', 
			   'FILTER_STATUS', v.other_annotation->'ADSP_WGS'->>'FILTER_STATUS')) 
	ELSE NULL END, '{}') AS adsp_qc		  
	FROM AnnotatedVDB.Variant v
	WHERE LEFT(v.metaseq_id, 50) = LEFT(metaseqId, 50)
	AND v.metaseq_id = metaseqId
	AND CASE WHEN LENGTH(refSnpId) = 0 THEN TRUE
	ELSE v.ref_snp_id = refSnpId END 
	AND v.chromosome = chrm;
END;

$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_other_annotation_by_primary_key(variantPK TEXT)
       RETURNS TABLE(record_primary_key TEXT, adsp_qc JSONB) AS $$

DECLARE metaseqId TEXT;
DECLARE refSnpId TEXT;
DECLARE chrm TEXT;
BEGIN
	
	SELECT split_part(variantPK, '_', 1) INTO metaseqId;
	SELECT split_part(variantPK, '_', 2) INTO refSnpId;
	SELECT 'chr' || split_part(variantPK, ':', 1)::text INTO chrm;

	RETURN QUERY

	SELECT variantPK AS variant_primary_key, 
	v.other_annotation
	FROM AnnotatedVDB.Variant v
	WHERE LEFT(v.metaseq_id, 50) = LEFT(metaseqId, 50)
	AND v.metaseq_id = metaseqId
	AND CASE WHEN LENGTH(refSnpId) = 0 THEN TRUE
	ELSE v.ref_snp_id = refSnpId END 
	AND v.chromosome = chrm;
END;

$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION get_annotated_variant_attributes_by_primary_key(variantPK TEXT)
       RETURNS TABLE(record_primary_key TEXT, adsp_qc JSONB) AS $$

DECLARE metaseqId TEXT;
DECLARE refSnpId TEXT;
DECLARE chrm TEXT;
BEGIN
	
	SELECT split_part(variantPK, '_', 1) INTO metaseqId;
	SELECT split_part(variantPK, '_', 2) INTO refSnpId;
	SELECT 'chr' || split_part(variantPK, ':', 1)::text INTO chrm;

	RETURN QUERY

	SELECT variantPK AS variant_primary_key, 
	v.other_annotation
	FROM AnnotatedVDB.Variant v
	WHERE LEFT(v.metaseq_id, 50) = LEFT(metaseqId, 50)
	AND v.metaseq_id = metaseqId
	AND CASE WHEN LENGTH(refSnpId) = 0 THEN TRUE
	ELSE v.ref_snp_id = refSnpId END 
	AND v.chromosome = chrm;
END;

$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION allele_frequencies(variantPK TEXT)
       RETURNS JSONB AS $$

DECLARE metaseqId TEXT;
DECLARE refSnpId TEXT;
DECLARE chrm TEXT;
DECLARE af JSONB;
BEGIN
	
	SELECT split_part(variantPK, '_', 1) INTO metaseqId;
	SELECT split_part(variantPK, '_', 2) INTO refSnpId;
	SELECT 'chr' || split_part(variantPK, ':', 1)::text INTO chrm;

	SELECT 
	v.allele_frequencies INTO af
	FROM AnnotatedVDB.Variant v
	WHERE LEFT(v.metaseq_id, 50) = LEFT(metaseqId, 50)
	AND v.metaseq_id = metaseqId
	AND CASE WHEN LENGTH(refSnpId) = 0 THEN TRUE
	ELSE v.ref_snp_id = refSnpId END 
	AND v.chromosome = chrm;

	RETURN af;
END;

$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION is_adsp_variant(variantPK TEXT)
       RETURNS BOOLEAN AS $$
DECLARE flag BOOLEAN;

DECLARE metaseqId TEXT;
DECLARE refSnpId TEXT;
DECLARE chrm TEXT;
BEGIN
	
	SELECT split_part(variantPK, '_', 1) INTO metaseqId;
	SELECT split_part(variantPK, '_', 2) INTO refSnpId;
	SELECT 'chr' || split_part(variantPK, ':', 1)::text INTO chrm;

	SELECT CASE WHEN is_adsp_variant IS NULL THEN FALSE ELSE is_adsp_variant END INTO flag
	FROM AnnotatedVDB.Variant v
	WHERE LEFT(v.metaseq_id, 50) = LEFT(metaseqId, 50)
	AND v.metaseq_id = metaseqId
	AND CASE WHEN LENGTH(refSnpId) = 0 THEN TRUE
	ELSE v.ref_snp_id = refSnpId END 
	AND v.chromosome = chrm;
RETURN flag;
END;

$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION adsp_most_severe_consequence(variantPK TEXT) 
RETURNS JSONB AS $$
DECLARE msc JSONB;
DECLARE metaseqId TEXT;
DECLARE refSnpId TEXT;
DECLARE chrm TEXT;
BEGIN
	
	SELECT split_part(variantPK, '_', 1) INTO metaseqId;
	SELECT split_part(variantPK, '_', 2) INTO refSnpId;
	SELECT 'chr' || split_part(variantPK, ':', 1)::text INTO chrm;

	SELECT adsp_most_severe_consequence INTO msc
	FROM AnnotatedVDB.Variant v
	WHERE LEFT(v.metaseq_id, 50) = LEFT(metaseqId, 50)
	AND v.metaseq_id = metaseqId
	AND CASE WHEN LENGTH(refSnpId) = 0 THEN TRUE
	ELSE v.ref_snp_id = refSnpId END 
	AND v.chromosome = chrm;

RETURN msc;

END;

$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION cadd(variantPK TEXT)
       RETURNS JSONB AS $$
DECLARE cs JSONB;
DECLARE metaseqId TEXT;
DECLARE refSnpId TEXT;
DECLARE chrm TEXT;
BEGIN
	
	SELECT split_part(variantPK, '_', 1) INTO metaseqId;
	SELECT split_part(variantPK, '_', 2) INTO refSnpId;
	SELECT 'chr' || split_part(variantPK, ':', 1)::text INTO chrm;

	SELECT cadd_scores INTO cs
	FROM AnnotatedVDB.Variant v
	WHERE LEFT(v.metaseq_id, 50) = LEFT(metaseqId, 50)
	AND v.metaseq_id = metaseqId
	AND CASE WHEN LENGTH(refSnpId) = 0 THEN TRUE
	ELSE v.ref_snp_id = refSnpId END 
	AND v.chromosome = chrm;
RETURN cs;
END;

$$ LANGUAGE plpgsql;
