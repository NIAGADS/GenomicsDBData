/* CREATE FUNCTION my_schema.users_name(u my_schema.users)
RETURNS varchar AS $$
SELECT u.first_name || ' ' || u.last_name;
$$ LANGUAGE SQL stable; */

/* DROP FUNCTION has_annotation;
DROP FUNCTION sequence_allele_display CASCADE;
DROP FUNCTION most_severe_consequence  CASCADE;
DROP FUNCTION msc_impacted_gene_link  CASCADE;
DROP FUNCTION msc_impacted_transcript  CASCADE;
DROP FUNCTION msc_is_coding  CASCADE;
DROP FUNCTION adsp_variant_display_flag CASCADE;
DROP FUNCTION adsp_wes_display_flag CASCADE;
DROP FUNCTION adsp_wgs_display_flag CASCADE;
DROP FUNCTION is_annotated_flag CASCADE; */

CREATE OR REPLACE FUNCTION most_severe_consequence(v NIAGADS.VariantGWASTopHits)
RETURNS text AS $$
	SELECT replace(array_to_string(json_array_cast_to_text((v.annotation->'ADSP_MOST_SEVERE_CONSEQUENCE'->'consequence_terms')::json), ','), '_', ' ');
$$ LANGUAGE SQL stable;


CREATE OR REPLACE FUNCTION msc_impacted_gene_link(v NIAGADS.VariantGWASTopHits)
RETURNS text AS $$
	SELECT build_link_attribute(v.annotation->'ADSP_MOST_SEVERE_CONSEQUENCE'->>'gene_symbol', '/record/gene/', v.annotation->'ADSP_MOST_SEVERE_CONSEQUENCE'->>'gene_id', 'view gene annotations')::text;
$$ LANGUAGE SQL stable;

CREATE OR REPLACE FUNCTION msc_impacted_transcript(v NIAGADS.VariantGWASTopHits)
RETURNS text AS $$
	SELECT build_link_attribute(v.annotation->'ADSP_MOST_SEVERE_CONSEQUENCE'->>'transcript_id',
	CASE
		WHEN 'GRCh37' = 'GRCh37'
		THEN '+ENSEMBL_TRANSCRIPT_URL_GRCh37+'
		ELSE '+ENSEMBL_TRANSCRIPT_URL_GRCh38+'
		END, NULL, 'view transript details from Ensembl' ||
	CASE
		WHEN 'GRCh37' = 'GRCh37'
		THEN ' GRCh37 Archive'
		ELSE ''
	END)::text;
$$ LANGUAGE SQL stable;


CREATE OR REPLACE FUNCTION msc_is_coding(v NIAGADS.VariantGWASTopHits)
RETURNS text AS $$
SELECT CASE WHEN (v.annotation->'ADSP_MOST_SEVERE_CONSEQUENCE'->>'consequence_is_coding')::BOOLEAN
THEN build_icon_attribute('Coding', 'fa-check', 'green', NULL, 'true')::text
ELSE NULL END;
$$ LANGUAGE SQL stable;


CREATE OR REPLACE FUNCTION adsp_variant_display_flag(v NIAGADS.VariantGWASTopHits)
RETURNS text AS $$
	SELECT CASE
	       WHEN v.is_adsp_variant
	       THEN build_icon_attribute('ADSP Variant', 'fa-check', 'red', NULL, true::text)::text
	       ELSE NULL END;
$$ LANGUAGE SQL stable;


