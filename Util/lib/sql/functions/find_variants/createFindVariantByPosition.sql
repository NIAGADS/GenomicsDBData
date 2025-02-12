-- finds variants at chr:pos

DROP FUNCTION IF EXISTS find_variant_by_position;
CREATE OR REPLACE FUNCTION find_variant_by_position(chr TEXT, pos INTEGER, firstHitOnly BOOLEAN DEFAULT FALSE) 
    RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, 
                    metaseq_id TEXT, alleles TEXT, variant_class TEXT, length INTEGER,
                is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB) AS $$

DECLARE binIndex LTREE;

BEGIN
    SELECT find_bin_index(chr, pos, pos) INTO binIndex;

	RETURN QUERY

	SELECT v.record_primary_key::TEXT, v.ref_snp_id, v.metaseq_id,
        v.display_attributes->>'display_allele' AS alleles,
        v.display_attributes->>'variant_class_abbrev' AS variant_class,
        CASE WHEN v.display_attributes->>'location_start' = v.display_attributes->>'location_end'
            THEN 1
            ELSE (v.display_attributes->>'location_end')::int - (v.display_attributes->>'location_start')::int 
            END AS length,
        CASE WHEN v.is_adsp_variant THEN TRUE ELSE FALSE END, v.bin_index,
        get_variant_annotation_summary(row_to_json(v)::jsonb) AS annotation
	FROM AnnotatedVDB.Variant v -- , bin b
	WHERE chromosome = chr AND v.bin_index @> binIndex 
    AND v.metaseq_id NOT LIKE '%R:I%' -- legacy from the adsp sv c/c
    AND int8range(pos, pos, '[]') && int8range(v.position, v.position, '[]')	
    ORDER BY metaseq_id -- LIMIT 1 hangs the query for some reason; see for ORDER BY solution https://stackoverflow.com/a/27237698
	LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;

-- same as above, just also returns normalized metaseq_id FOR INTERNAL USE
DROP FUNCTION IF EXISTS find_normalized_variant_by_position;
CREATE OR REPLACE FUNCTION find_normalized_variant_by_position(chr TEXT, pos INTEGER, firstHitOnly BOOLEAN DEFAULT FALSE) 
    RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT, 
                normalized_metaseq_id TEXT, alleles TEXT, variant_class TEXT, length INTEGER,
                is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB) AS $$

DECLARE 
    binIndex LTREE;
BEGIN

    SELECT find_bin_index(chr, pos, pos) INTO binIndex;

	RETURN QUERY
	SELECT v.record_primary_key::TEXT, v.ref_snp_id, v.metaseq_id,
        v.display_attributes->>'normalized_metaseq_id' AS normalized_metaseq_id,
        v.display_attributes->>'display_allele' AS alleles,
        v.display_attributes->>'variant_class_abbrev' AS variant_class,
        CASE WHEN v.display_attributes->>'location_start' = v.display_attributes->>'location_end'
            THEN 1
            ELSE (v.display_attributes->>'location_end')::int - (v.display_attributes->>'location_start')::int 
            END AS length,
        CASE WHEN v.is_adsp_variant THEN TRUE ELSE FALSE END, v.bin_index,
        get_variant_annotation_summary(row_to_json(v)::jsonb) AS annotation
	FROM AnnotatedVDB.Variant v
	WHERE chromosome = chr AND v.bin_index @> binIndex 
    AND v.metaseq_id NOT LIKE '%R:I%' -- legacy from the adsp sv c/c
    AND int8range(pos, pos, '[]') && int8range(v.position, v.position, '[]')	
    ORDER BY metaseq_id -- LIMIT 1 hangs the query for some reason; see for ORDER BY solution https://stackoverflow.com/a/27237698
	LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;

-- finds variants at chr:pos with a given allele


DROP FUNCTION IF EXISTS find_variant_by_position_and_allele(chr TEXT, pos INTEGER, allele TEXT, BOOLEAN);
CREATE OR REPLACE FUNCTION find_variant_by_position_and_allele(chr TEXT, pos INTEGER, allele TEXT, firstHitOnly BOOLEAN DEFAULT FALSE) 
    RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT, alleles TEXT, variant_class TEXT, length INTEGER,
        is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB) AS $$
DECLARE binIndex LTREE;

BEGIN
    SELECT find_bin_index(chr, pos, pos) INTO binIndex;
	RETURN QUERY
	SELECT v.record_primary_key::TEXT, v.ref_snp_id, v.metaseq_id,
        v.display_attributes->>'display_allele' AS alleles,
        v.display_attributes->>'variant_class_abbrev' AS variant_class,
        CASE WHEN v.display_attributes->>'location_start' = v.display_attributes->>'location_end'
            THEN 1
            ELSE (v.display_attributes->>'location_end')::int - (v.display_attributes->>'location_start')::int 
            END AS length,
        CASE WHEN v.is_adsp_variant THEN TRUE ELSE FALSE END, v.bin_index,
        get_variant_annotation_summary(row_to_json(v)::jsonb) AS annotation
	FROM AnnotatedVDB.Variant v
    WHERE chromosome = chr AND v.bin_index @> binIndex 
    AND int8range(pos, pos, '[]') && int8range(v.position, v.position, '[]')	

	AND CASE WHEN allele IS NOT NULL 
    THEN array_sort(ARRAY[split_part(v.metaseq_id, ':', 3), split_part(v.metaseq_id, ':', 4)]) @> ARRAY[allele] 
    ELSE TRUE END
    
	ORDER BY metaseq_id -- LIMIT 1 hangs the query for some reason; see for ORDER BY solution https://stackoverflow.com/a/27237698
	LIMIT CASE WHEN firstHitOnly THEN 1 END;
    
END;

$$ LANGUAGE plpgsql;
