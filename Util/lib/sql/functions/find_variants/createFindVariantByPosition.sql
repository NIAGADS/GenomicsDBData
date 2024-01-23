-- finds variants at chr:pos

--DROP FUNCTION find_variant_by_position;

CREATE OR REPLACE FUNCTION get_variant_pk_by_position(lookup TEXT, firstHitOnly BOOLEAN DEFAULT FALSE) 
       RETURNS TABLE(lookup_value TEXT, record_primary_key TEXT) AS $$

DECLARE chrm TEXT;
DECLARE pos INT;
BEGIN
	SELECT 'chr' || split_part(lookup, ':', 1) INTO chrm;
	SELECT (split_part(lookup, ':', 2))::int INTO pos;
	
	RETURN QUERY
	WITH bin AS (SELECT find_bin_index(chrm, pos, pos) bin_index)
	SELECT lookup AS lookup_value, v.record_primary_key::TEXT
	FROM AnnotatedVDB.Variant v, bin b
	WHERE chromosome = chrm AND v.bin_index @> b.bin_index
        AND int8range(pos, pos, '[]') && int8range(v.position, v.position, '[]')
	AND v.record_primary_key NOT LIKE '%:I%'
	LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS find_variant_by_position(chr TEXT, pos INTEGER, firstHitOnly BOOLEAN);
CREATE OR REPLACE FUNCTION find_variant_by_position(chr TEXT, pos INTEGER, firstHitOnly BOOLEAN DEFAULT FALSE) 
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
     'allele_frequencies', v.allele_frequencies,
     'cadd_scores', v.cadd_scores,
	 'most_severe_consequence', v.adsp_most_severe_consequence,
	 'ranked_consequences', v.adsp_ranked_consequences,
	 'ADSP_QC', v.adsp_qc #- '{17k,info,AF}' #- '{17k,info,AC}' #- '{17k,info,AN}',
	 'mapped_coordinates', COALESCE(v.other_annotation->'GRCh37' || '{"assembly":"GRCh37"}', v.other_annotation->'GRCh38' || '{"assembly":"GRCh38"}')) AS annotation
	FROM AnnotatedVDB.Variant v, bin b
	WHERE chromosome = chr AND v.bin_index @> b.bin_index
        AND int8range(pos, pos, '[]') && int8range(v.position, v.position, '[]')	
    ORDER BY record_primary_key -- LIMIT 1 hangs the query for some reason; see for ORDER BY solution https://stackoverflow.com/a/27237698
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
