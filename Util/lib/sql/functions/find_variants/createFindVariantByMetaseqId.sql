-- finds variant by chr:pos:ref:alt id

CREATE OR REPLACE FUNCTION generate_rc_metaseq_id(metaseqID TEXT)
RETURNS TEXT AS $$
DECLARE altId TEXT;
BEGIN
	WITH _array AS (SELECT regexp_split_to_array(metaseqId, ':') AS VALUES)
	SELECT CONCAT(_array.values[1], ':'::text, _array.values[2], ':'::text, reverse_complement(_array.values[3] || ':' || _array.values[4]))
	INTO altId FROM _array;
	RETURN altId;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION generate_alt_metaseq_id(metaseqId TEXT)
            RETURNS TEXT AS $$
DECLARE
	altId TEXT;
BEGIN
	WITH _array AS (SELECT regexp_split_to_array(metaseqId, ':') AS VALUES)
	SELECT CONCAT(_array.values[1], ':'::text, _array.values[2], ':'::text, _array.values[4], ':'::text, _array.values[3]) INTO altId FROM _array;
	RETURN altId;
END;

$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION find_variant_by_metaseq_id_variations(metaseqId TEXT, firstHitOnly BOOLEAN DEFAULT FALSE)
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
       	             has_genomicsdb_annotation BOOLEAN, is_adsp_variant BOOLEAN, bin_index LTREE, match_rank INTEGER, match_type TEXT) AS $$

BEGIN
	RETURN QUERY
    	SELECT *, 1 AS match_rank, 'exact' AS match_type
	FROM find_variant_by_metaseq_id(metaseqId, firstHitOnly)
        UNION ALL
        SELECT *, 2 AS match_rank, 'switch' AS match_type
	FROM find_variant_by_metaseq_id(generate_alt_metaseq_id(metaseqId), firstHitOnly)
	UNION ALL
	SELECT *, 3 AS match_rank, 'reverse comp' AS match_type
	FROM find_variant_by_metaseq_id(generate_rc_metaseq_id(metaseqId), firstHitOnly)
	UNION ALL
	SELECT *, 4 AS match_rank, 'reverse_comp//switch' AS match_type
	FROM find_variant_by_metaseq_id(generate_alt_metaseq_id(generate_rc_metaseq_id(metaseqId)), firstHitOnly)	
	ORDER BY match_rank ASC
        LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION find_variant_by_metaseq_id(metaseqId TEXT, firstHitOnly BOOLEAN DEFAULT FALSE)
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
       	             has_genomicsdb_annotation BOOLEAN, is_adsp_variant BOOLEAN, bin_index LTREE) AS $$
BEGIN
	RETURN QUERY
	SELECT v.record_primary_key, v.ref_snp_id, v.metaseq_id, v.has_genomicsdb_annotation, v.is_adsp_variant,
	v.bin_index
	FROM AnnotatedVDB.Variant v
	WHERE v.metaseq_id = metaseqId
	AND LEFT(v.metaseq_id, 50) = LEFT(metaseqId, 50)
	AND chromosome = 'chr' || split_part(metaseqId, ':', 1)::text
	LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION find_variant_by_metaseq_id(metaseqId TEXT, chrm TEXT, firstHitOnly BOOLEAN DEFAULT FALSE)
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
       	             has_genomicsdb_annotation BOOLEAN, is_adsp_variant BOOLEAN, bin_index LTREE) AS $$
BEGIN
	RETURN QUERY
	SELECT v.record_primary_key, v.ref_snp_id, v.metaseq_id, v.has_genomicsdb_annotation, v.is_adsp_variant,
	v.bin_index
	FROM AnnotatedVDB.Variant v
	WHERE v.metaseq_id = metaseqId
	AND chromosome = chrm
	LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;

--DROP FUNCTION get_variant_annotation_by_metaseq_id(text,text,boolean);

CREATE OR REPLACE FUNCTION get_variant_annotation_by_metaseq_id(metaseqId TEXT, chrm TEXT, firstHitOnly BOOLEAN DEFAULT FALSE)
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
       	             has_genomicsdb_annotation BOOLEAN, is_adsp_variant BOOLEAN, bin_index LTREE,
adsp_most_severe_consequence JSONB, cadd_scores JSONB, allele_frequencies JSONB) AS $$

BEGIN
	RETURN QUERY
	SELECT v.record_primary_key, v.ref_snp_id, v.metaseq_id, v.has_genomicsdb_annotation, v.is_adsp_variant,
	v.bin_index, v.adsp_most_severe_consequence, v.cadd_scores, v.allele_frequencies 
	FROM AnnotatedVDB.Variant v
	WHERE v.metaseq_id = metaseqId
	AND chromosome = chrm
	LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_variant_annotation_by_metaseq_id(metaseqId TEXT, firstHitOnly BOOLEAN DEFAULT FALSE)
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
       	             has_genomicsdb_annotation BOOLEAN, is_adsp_variant BOOLEAN, bin_index LTREE,
adsp_most_severe_consequence JSONB, cadd_scores JSONB, allele_frequencies JSONB) AS $$

BEGIN
	RETURN QUERY
	SELECT v.record_primary_key, v.ref_snp_id, v.metaseq_id, v.has_genomicsdb_annotation, v.is_adsp_variant,
	v.bin_index, v.adsp_most_severe_consequence, v.cadd_scores, v.allele_frequencies 
	FROM AnnotatedVDB.Variant v
	WHERE v.metaseq_id = metaseqId
	AND chromosome = 'chr' || split_part(metaseqId, ':', 1)::text
	LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;
