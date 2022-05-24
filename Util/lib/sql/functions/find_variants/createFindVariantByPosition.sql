-- finds variants at chr:pos

--DROP FUNCTION find_variant_by_position;


DROP FUNCTION IF EXISTS find_variant_by_position(chr CHARACTER VARYING, pos INTEGER, firstHitOnly BOOLEAN);
CREATE OR REPLACE FUNCTION find_variant_by_position(chr CHARACTER VARYING, pos INTEGER, firstHitOnly BOOLEAN DEFAULT FALSE) 
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT, alleles TEXT, variant_class TEXT,
       	             is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB) AS $$
BEGIN
	RETURN QUERY
	WITH bin AS (SELECT find_bin_index(chr, pos, pos) bin_index)
	SELECT v.record_primary_key::TEXT, v.ref_snp_id, v.metaseq_id,
 	v.display_attributes->>'display_allele' AS alleles,
	v.display_attributes->>'variant_class_abbrev' AS variant_class,
	CASE WHEN v.is_adsp_variant THEN TRUE ELSE FALSE END, v.bin_index,
	jsonb_build_object(
	 'associations', v.gwas_flags,
	 'most_severe_consequence', v.adsp_most_severe_consequence,
	 'ADSP_QC', v.adsp_qc #- '{17k,info,AF}' #- '{17k,info,AC}' #- '{17k,info,AN}',
	 'mapped_coordinates', COALESCE(v.other_annotation->'GRCh37' || '{"assembly":"GRCh37"}', v.other_annotation->'GRCh38' || '{"assembly":"GRCh38"}')) AS annotation
	FROM AnnotatedVDB.Variant v, bin b
	WHERE chromosome = chr AND v.bin_index @> b.bin_index
        AND int8range(pos, pos, '[]') && int8range(v.position, v.position, '[]')	
	LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;

--DROP FUNCTION IF EXISTS get_variant_annotation_by_position(text,bigint,boolean);

-- CREATE OR REPLACE FUNCTION get_variant_annotation_by_position(chr TEXT, pos BIGINT, firstHitOnly BOOLEAN DEFAULT FALSE) 
--        RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
--        	             has_genomicsdb_annotation BOOLEAN, is_adsp_variant BOOLEAN, bin_index LTREE,
-- 		     adsp_most_severe_consequence JSONB, cadd_scores JSONB, allele_frequencies JSONB) AS $$
-- BEGIN
-- 	RETURN QUERY
-- 	SELECT v.record_primary_key, v.ref_snp_id, v.metaseq_id, v.has_genomicsdb_annotation, v.is_adsp_variant,
-- 	v.bin_index, v.adsp_most_severe_consequence, v.cadd_scores, v.allele_frequencies 
-- 	FROM AnnotatedVDB.Variant v
-- 	WHERE chromosome = chr AND location = pos
-- 	LIMIT CASE WHEN firstHitOnly THEN 1 END;
-- END;

-- $$ LANGUAGE plpgsql;
