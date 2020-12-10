-- finds variants at chr:pos

--DROP FUNCTION find_variant_by_position;



CREATE OR REPLACE FUNCTION find_variant_by_position(chr TEXT, pos BIGINT, firstHitOnly BOOLEAN DEFAULT FALSE) 
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
       	             has_genomicsdb_annotation BOOLEAN, is_adsp_variant BOOLEAN, bin_index LTREE) AS $$
BEGIN
	RETURN QUERY
	WITH bin AS (SELECT find_bin_index(chr, pos, pos) bin_index)
	SELECT v.record_primary_key, v.ref_snp_id, v.metaseq_id, v.has_genomicsdb_annotation, v.is_adsp_variant,
	v.bin_index
	FROM AnnotatedVDB.Variant v, bin b
	WHERE chromosome = chr AND v.bin_index @> b.bin_index
        AND int8range(pos, pos, '[]') && int8range(v.location, v.location, '[]')	
	LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;

--DROP FUNCTION get_variant_annotation_by_position(text,bigint,boolean);

CREATE OR REPLACE FUNCTION get_variant_annotation_by_position(chr TEXT, pos BIGINT, firstHitOnly BOOLEAN DEFAULT FALSE) 
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
       	             has_genomicsdb_annotation BOOLEAN, is_adsp_variant BOOLEAN, bin_index LTREE,
		     adsp_most_severe_consequence JSONB, cadd_scores JSONB, allele_frequencies JSONB) AS $$
BEGIN
	RETURN QUERY
	SELECT v.record_primary_key, v.ref_snp_id, v.metaseq_id, v.has_genomicsdb_annotation, v.is_adsp_variant,
	v.bin_index, v.adsp_most_severe_consequence, v.cadd_scores, v.allele_frequencies 
	FROM AnnotatedVDB.Variant v
	WHERE chromosome = chr AND location = pos
	LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;
