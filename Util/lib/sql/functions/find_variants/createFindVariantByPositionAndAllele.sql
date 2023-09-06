-- finds variants at chr:pos with a given allele


DROP FUNCTION IF EXISTS find_variant_by_position_and_allele(chr TEXT, pos INTEGER, allele TEXT, BOOLEAN);
CREATE OR REPLACE FUNCTION find_variant_by_position_and_allele(chr TEXT, pos INTEGER, allele TEXT, firstHitOnly BOOLEAN DEFAULT FALSE) 
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT, alleles TEXT, variant_class TEXT,
       	             is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB) AS $$
BEGIN
	RETURN QUERY
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
	FROM AnnotatedVDB.Variant v
	WHERE v.chromosome = chr AND v.bin_index = (SELECT find_bin_index(chr, pos, pos)) AND POSITION = pos
	AND CASE WHEN allele IS NOT NULL THEN array_sort(ARRAY[split_part(v.metaseq_id, ':', 3), split_part(v.metaseq_id, ':', 4)]) @> ARRAY[allele] ELSE TRUE END
	LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;
