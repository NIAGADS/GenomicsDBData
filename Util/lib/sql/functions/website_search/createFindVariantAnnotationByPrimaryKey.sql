CREATE OR REPLACE FUNCTION get_variant_linkage(variantPK TEXT)
       RETURNS TABLE(record_primary_key TEXT, linkage JSONB) AS $$

DECLARE chrm TEXT;
DECLARE pos INT;
DECLARE binIndex LTREE;
DECLARE vDetails JSONB;
BEGIN
	SELECT details INTO vDetails FROM get_variant_display_details(variantPK);
	SELECT vDetails->>'chromosome' INTO chrm;
	SELECT (vDetails->>'position')::int INTO pos;
	SELECT (vDetails->>'bin_index')::LTREE INTO binIndex;

	RETURN QUERY

	SELECT variantPK AS variant_primary_key,
	jsonb_build_object('population_id', population_protocol_app_node_id,
	'locations', locations,
	'distance', distance,
	'minor_allele_frequency', minor_allele_frequency,
	'r_squared', r_squared,
	'd_prime', d_prime,
	'variants', variants) AS linkage
        FROM Results.VariantLD r 
	WHERE r.locations @> ARRAY[pos]
	AND r.bin_index @> binIndex
	AND r.chromosome = chrm;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_variant_display_details(variantPK TEXT)
       RETURNS TABLE(record_primary_key TEXT, details JSONB) AS $$

DECLARE chrm TEXT;
BEGIN
	
	SELECT 'chr' || split_part(variantPK, ':', 1)::text INTO chrm;

	RETURN QUERY

	WITH msc AS (SELECT variantPK AS record_primary_key,
              most_severe_consequence(variantPK),
	      most_severe_consequence(variantPK, TRUE)::jsonb AS conseq)
	SELECT v.record_primary_key::text,
	jsonb_build_object(
	'chromosome', chromosome,
	'position', position,
	 'location', CASE WHEN v.display_attributes->>'location_start' = v.display_attributes->>'location_end' THEN position::text 
	 ELSE v.display_attributes->>'location_start' || ' - ' || (v.display_attributes->>'location_end')::text END,
	'ref_snp_id', ref_snp_id,
	'metaseq_id', metaseq_id,
	'display_id', truncate_str(metaseq_id, 30)::text,
	'bin_index', bin_index,
	'display_allele', display_attributes->>'display_allele',
	'variant_class', display_attributes->>'variant_class',
	'variant_class_abbrev', display_attributes->>'variant_class_abbrev',
	'is_adsp_variant', is_adsp_variant,
	'cadd', cadd_scores,
	'most_severe_consequence', jsonb_build_object(
	  			   'conseq', msc.most_severe_consequence,
				   'impacted_gene', msc.conseq->>'gene_id',
				   'impacted_gene_symbol', msc.conseq->>'gene_symbol',
				   'impact', msc.conseq->>'impact',
				   'is_coding', (msc.conseq->>'consequence_is_coding')::boolean,
				   'codon_change', msc.conseq->>'codons',
				   'amino_acid_change',  msc.conseq->>'amino_acids')
				   ) AS details
	FROM AnnotatedVDB.Variant v, msc
	WHERE v.record_primary_key = variantPK
	AND msc.record_primary_key = variantPK
	AND v.chromosome = chrm
	LIMIT 1; -- temp fix b/c of duplicates
END;

$$ LANGUAGE plpgsql;
