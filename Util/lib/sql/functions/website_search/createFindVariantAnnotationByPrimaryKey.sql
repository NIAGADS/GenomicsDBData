-- lookups against AnnotatedVDB.Variant

CREATE OR REPLACE FUNCTION get_variant_annotation_by_primary_key(variantPK TEXT)
       RETURNS TABLE(record_primary_key TEXT,
       adsp_most_severe_consequence JSONB, cadd_scores JSONB, allele_frequencies JSONB) AS $$

DECLARE chrm TEXT;
BEGIN
	
	SELECT 'chr' || split_part(variantPK, ':', 1)::text INTO chrm;

	RETURN QUERY

	SELECT variantPK AS variant_primary_key, 
	v.adsp_most_severe_consequence, 
	v.cadd_scores, 
	v.allele_frequencies 
	FROM AnnotatedVDB.Variant v
	WHERE v.record_primary_key = variantPK
	AND v.chromosome = chrm;
END;

$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_summary_annotation_by_primary_key(variantPK TEXT)
       RETURNS TABLE(record_primary_key TEXT, metaseq_id TEXT, display_metaseq_id TEXT, ref_snp_id TEXT,
       is_adsp_variant BOOLEAN, most_severe_consequence TEXT, msc_impact TEXT, display_allele TEXT, variant_class_abbrev TEXT)
    AS $$  
DECLARE metaseqId TEXT;
DECLARE refSnpId TEXT;
DECLARE chrm TEXT;
DECLARE ref_allele TEXT;
DECLARE alt_allele TEXT;
DECLARE POSITION INTEGER;
BEGIN
	-- metaseq_id, display_metaseq_id, ref_snp_id, is_adsp_variant, variant_class_abbrev, display_allele, ms.impact, ms.conseq
	SELECT split_part(variantPK, '_', 1) INTO metaseqId;
	SELECT split_part(variantPK, '_', 2) INTO refSnpId;
	SELECT 'chr' || split_part(variantPK, ':', 1)::text INTO chrm;

	SELECT split_part(metaseqId, ':', 3) INTO ref_allele;
	SELECT split_part(metaseqId, ':', 4) INTO alt_allele;
	SELECT split_part(metaseqId, ':', 2)::integer INTO position;

	RETURN QUERY

	SELECT variantPK AS variant_primary_key,
	v.metaseq_id,
	truncate_str(v.metaseq_id, 27) AS display_metaseq_id,
	v.ref_snp_id::text,
	v.is_adsp_variant,
	v.adsp_ms_consequence AS most_severe_consequence,
	v.adsp_most_severe_consequence->>'impact' AS msc_impact,
	da.display_allele,
	da.variant_class_abbrev
	FROM AnnotatedVDB.Variant v,
	normalize_alleles(ref_allele, alt_allele) na, 
	display_allele_attributes(ref_allele, alt_allele, na.ref, na.alt, position) da
	WHERE LEFT(v.metaseq_id, 50) = LEFT(metaseqId, 50)
	AND v.metaseq_id = metaseqId
	AND CASE WHEN LENGTH(refSnpId) = 0 THEN TRUE
	ELSE v.ref_snp_id = refSnpId END 
	AND v.chromosome = chrm;


END;

$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_adsp_qc_by_primary_key(variantPK TEXT)
       RETURNS TABLE(record_primary_key TEXT, adsp_qc JSONB) AS $$

DECLARE chrm TEXT;
BEGIN
	
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
       RETURNS TABLE(record_primary_key TEXT, annotation JSONB) AS $$

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

	SELECT is_adsp_variant INTO flag
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

-- qw('transcript regulatory_feature motif_feature intergenic')

CREATE OR REPLACE FUNCTION adsp_ranked_consequences(variantPK TEXT, conseq_type TEXT)
       RETURNS JSONB AS $$

DECLARE conseq JSONB;
DECLARE metaseqId TEXT;
DECLARE refSnpId TEXT;
DECLARE chrm TEXT;
BEGIN
	
	SELECT split_part(variantPK, '_', 1) INTO metaseqId;
	SELECT split_part(variantPK, '_', 2) INTO refSnpId;
	SELECT 'chr' || split_part(variantPK, ':', 1)::text INTO chrm;

	SELECT 
	CASE WHEN LOWER(conseq_type) = 'all' THEN adsp_ranked_consequences
	WHEN LOWER(conseq_type) = 'transcript' THEN adsp_ranked_consequences->'transcript_consequences'
	WHEN LOWER(conseq_type) = 'regulatory' THEN adsp_ranked_consequences->'regulatory_feature_consequences'
	WHEN LOWER(conseq_type) = 'motif' THEN adsp_ranked_consequences->'motif_feature_consequences'
	WHEN LOWER(conseq_type) = 'intergenic' THEN adsp_ranked_consequences->'intergenic_consequences'
	END INTO conseq

	FROM AnnotatedVDB.Variant v
	WHERE LEFT(v.metaseq_id, 50) = LEFT(metaseqId, 50)
	AND v.metaseq_id = metaseqId
	AND CASE WHEN LENGTH(refSnpId) = 0 THEN TRUE
	ELSE v.ref_snp_id = refSnpId END 
	AND v.chromosome = chrm;
RETURN conseq;
END;

$$ LANGUAGE plpgsql;
