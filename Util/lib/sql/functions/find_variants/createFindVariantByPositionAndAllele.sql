-- finds variants at chr:pos with a given allele

CREATE OR REPLACE FUNCTION find_variant_by_position_and_allele(chr TEXT, pos INTEGER, allele TEXT) 
       RETURNS TABLE(variant_id INTEGER) AS $$
BEGIN
	RETURN QUERY
	SELECT v.variant_id, ref_allele, alt_allele
	FROM NIAGADS.Variant v 
	WHERE bin_index = (SELECT find_bin_index(chr, pos, pos)) AND POSITION = pos
	AND (ref_allele = allele OR alt_allele = allele);
END;

$$ LANGUAGE plpgsql;
