-- finds variants at chr:pos with a given allele

DROP FUNCTION IF EXISTS find_variant_by_position_and_allele(chr TEXT, pos INTEGER, allele TEXT, BOOLEAN);
CREATE OR REPLACE FUNCTION find_variant_by_position_and_allele(chr TEXT, pos INTEGER, allele TEXT, firstHitOnly BOOLEAN DEFAULT FALSE)
        RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
       	             is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB) AS $$  
BEGIN
	RETURN QUERY
	SELECT v.record_primary_key, v.ref_snp_id, v.metaseq_id, v.is_adsp_variant, v.bin_index,
	jsonb_build_object(
	 'GenomicsDB', v.other_annotation->'GenomicsDB',
	 'mapped_coordinates', COALESCE(v.other_annotation->'GRCh37' || '{"assembly":"GRCh37"}', v.other_annotation->'GRCh38' || '{"assembly":"GRCh38"}')) AS annotation
	FROM AnnotatedVDB.Variant v
	WHERE v.chromosome = chr AND v.bin_index = (SELECT find_bin_index(chr, pos, pos)) AND v.location = pos
	AND CASE WHEN allele IS NOT NULL THEN array_sort(ARRAY[split_part(v.metaseq_id, ':', 3), split_part(v.metaseq_id, ':', 4)]) @> ARRAY[allele] ELSE TRUE END

	AND (v.metaseq_id NOT LIKE '%?%'
	AND v.metaseq_id SIMILAR TO '%(A|C|G|T)%' AND v.metaseq_id NOT SIMILAR TO '%(R|I|N|\?)%')

	LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;
