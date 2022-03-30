-- finds variants at chr:pos with a given allele



CREATE OR REPLACE FUNCTION find_variant_by_position_and_allele(chr CHARACTER VARYING, pos INTEGER, allele TEXT)
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
       	             is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB) AS $$
BEGIN
	RETURN QUERY
	SELECT v.record_primary_key::TEXT, v.ref_snp_id, v.metaseq_id, v.is_adsp_variant, v.bin_index,
	jsonb_build_object(
	 'GenomicsDB', v.other_annotation->'GenomicsDB',
	 'mapped_coordinates', COALESCE(v.other_annotation->'GRCh37', v.other_annotation->'GRCh38')) AS annotation
	FROM AnnotatedVDB.Variant v
	WHERE v.chromosome = chr AND v.bin_index = (SELECT find_bin_index(chr, pos, pos)) AND POSITION = pos
	AND CASE WHEN allele IS NOT NULL THEN array_sort(ARRAY[split_part(v.metaseq_id, ':', 3), split_part(v.metaseq_id, ':', 4)]) @> ARRAY[allele] ELSE TRUE END;
END;

$$ LANGUAGE plpgsql;
