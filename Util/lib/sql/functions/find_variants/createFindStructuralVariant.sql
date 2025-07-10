DROP FUNCTION IF EXISTS find_structural_variant_by_id(variantId TEXT);
CREATE OR REPLACE FUNCTION find_structural_variant_by_id(variantId TEXT)
    RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT, 
                alleles TEXT, variant_class TEXT, chromosome CHARACTER VARYING, "position" INTEGER, length INTEGER,
                is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB) AS $$
    DECLARE chrm TEXT;
BEGIN
    SELECT LOWER(split_part(variantId, '_', 2)) INTO chrm;
	RETURN QUERY

	SELECT v.record_primary_key::TEXT, v.ref_snp_id, v.metaseq_id,
    v.display_attributes->>'display_allele' AS alleles,
	v.display_attributes->>'variant_class_abbrev' AS variant_class,
    v.chromosome,
    v.position,
    (v.display_attributes->>'location_end')::int - (v.display_attributes->>'location_start')::int AS length,
	CASE WHEN v.is_adsp_variant THEN TRUE ELSE FALSE END AS is_adsp_variant, v.bin_index,
	get_variant_annotation_summary(row_to_json(v)::jsonb) AS annotation
	FROM AnnotatedVDB.Variant v
	WHERE v.record_primary_key = variantId
	AND v.chromosome = chrm;
END;

$$ LANGUAGE plpgsql;