CREATE OR REPLACE FUNCTION adsp_variant_flag(flag BOOLEAN)
RETURNS text AS $$
	SELECT CASE
	       WHEN flag
	       THEN build_icon_attribute(NULL, 'fa-check', 'red', NULL, true::text)::text
	       ELSE NULL END;
$$ LANGUAGE SQL stable;


CREATE OR REPLACE FUNCTION consequence_terms(consequence JSONB)
RETURNS text AS $$
	SELECT replace(array_to_string(json_array_cast_to_text((consequence->'consequence_terms')::json), ','), '_', ' ');
$$ LANGUAGE SQL stable;

CREATE OR REPLACE FUNCTION most_severe_consequence(variantPK TEXT, returnJson BOOLEAN DEFAULT FALSE)
RETURNS text AS $$
DECLARE
chrm TEXT;
DECLARE msc TEXT;
BEGIN
	SELECT 'chr' || split_part(variantPK, ':', 1)::text INTO chrm;
	SELECT CASE WHEN returnJson THEN (adsp_most_severe_consequence)::TEXT
	ELSE most_severe_consequence(adsp_most_severe_consequence) END INTO msc
	FROM AnnotatedVDB.Variant
	WHERE record_primary_key = variantPK
	AND chromosome = chrm;
	RETURN msc;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION msc_impacted_gene_link(consequence JSONB)
RETURNS text AS $$
	SELECT gene_record_link(consequence->>'gene_id', consequence->>'gene_symbol', FALSE);
$$ LANGUAGE SQL stable;


CREATE OR REPLACE FUNCTION msc_impacted_gene(consequence JSONB)
RETURNS text AS $$
	SELECT consequence->>'gene_id';
$$ LANGUAGE SQL stable;


CREATE OR REPLACE FUNCTION msc_is_coding(consequence JSONB)
RETURNS text AS $$
SELECT (consequence->>'consequence_is_coding')::BOOLEAN;
$$ LANGUAGE SQL stable;

CREATE OR REPLACE FUNCTION msc_is_coding_flag(consequence JSONB)
RETURNS text AS $$
SELECT CASE WHEN (consequence->>'consequence_is_coding')::BOOLEAN
THEN build_icon_attribute('Coding', 'fa-check', 'green', NULL, 'true')::text
ELSE NULL END;
$$ LANGUAGE SQL stable;

CREATE OR REPLACE FUNCTION adsp_ranked_consequences(variantPK TEXT, conseq_type TEXT)
       RETURNS JSONB AS $$

DECLARE conseq JSONB;
DECLARE chrm TEXT;
BEGIN
	
	SELECT 'chr' || split_part(variantPK, ':', 1)::text INTO chrm;

	SELECT 
	CASE WHEN LOWER(conseq_type) = 'all' THEN adsp_ranked_consequences
	WHEN LOWER(conseq_type) = 'transcript' THEN adsp_ranked_consequences->'transcript_consequences'
	WHEN LOWER(conseq_type) = 'regulatory' THEN adsp_ranked_consequences->'regulatory_feature_consequences'
	WHEN LOWER(conseq_type) = 'motif' THEN adsp_ranked_consequences->'motif_feature_consequences'
	WHEN LOWER(conseq_type) = 'intergenic' THEN adsp_ranked_consequences->'intergenic_consequences'
	END INTO conseq

	FROM AnnotatedVDB.Variant v
	WHERE v.record_primary_key = variantPK
	AND v.chromosome = chrm;
RETURN conseq;
END;

$$ LANGUAGE plpgsql;




