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

CREATE OR REPLACE FUNCTION has_annotation(v NIAGADS.Variant) 
RETURNS boolean AS $$ 
	SELECT CASE WHEN v.annotation->>'ADSP_WGS_FILTER' IS NOT NULL
	OR v.annotation->>'ADSP_WES_FILTER' IS NOT NULL
	OR v.annotation->>'GWAS' IS NOT NULL
	THEN TRUE ELSE FALSE END
$$ LANGUAGE SQL stable;

CREATE OR REPLACE FUNCTION sequence_allele_display(v NIAGADS.Variant)
RETURNS text AS $$
	SELECT build_text_attribute('[' || v.sequence_allele || ']', NULL, 'red')::text;
$$ LANGUAGE SQL stable;

CREATE OR REPLACE FUNCTION most_severe_consequence(v NIAGADS.Variant)
RETURNS text AS $$
	SELECT multi_replace(v.annotation->'VEP_MS_CONSEQUENCE'->>'consequence_terms', ARRAY[']' , '[', '_', ', ', '"'], ARRAY['', '', ' ', ' & ', '']);
$$ LANGUAGE SQL stable;

CREATE OR REPLACE FUNCTION msc_impacted_gene_link(v NIAGADS.Variant)
RETURNS text AS $$
	SELECT build_link_attribute(v.annotation->'VEP_MS_CONSEQUENCE'->>'gene_symbol', '/record/gene/', v.annotation->'VEP_MS_CONSEQUENCE'->>'gene_id', 'view gene annotations')::text;
$$ LANGUAGE SQL stable;

CREATE OR REPLACE FUNCTION msc_impacted_transcript(v NIAGADS.Variant)
RETURNS text AS $$
	SELECT build_link_attribute(v.annotation->'VEP_MS_CONSEQUENCE'->>'transcript_id',
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


CREATE OR REPLACE FUNCTION msc_is_coding(v NIAGADS.Variant)
RETURNS text AS $$
SELECT CASE WHEN (v.annotation->'VEP_MS_CONSEQUENCE'->>'is_coding')::BOOLEAN
THEN build_icon_attribute('Coding', 'fa-check', 'green', NULL, 'true')::text
ELSE NULL END;
$$ LANGUAGE SQL stable;

CREATE OR REPLACE FUNCTION adsp_variant_display_flag(v NIAGADS.Variant)
RETURNS text AS $$
	SELECT CASE
	       WHEN v.is_adsp_variant
	       THEN build_icon_attribute('ADSP Variant', 'fa-check-square-o', 'red', NULL, true::text)::text
	       ELSE NULL END;
$$ LANGUAGE SQL stable;


CREATE OR REPLACE FUNCTION adsp_wes_display_flag(v NIAGADS.Variant)
RETURNS text AS $$
       SELECT CASE
       	      WHEN v.is_adsp_wes
	      THEN build_nonlink_badge_attribute('WES', true::text, NULL, 'red')::text
	      ELSE NULL END;
$$ LANGUAGE SQL stable;

CREATE OR REPLACE FUNCTION adsp_wgs_display_flag(v NIAGADS.Variant)
RETURNS text AS $$
	SELECT CASE
	       WHEN v.is_adsp_wgs
	       THEN build_nonlink_badge_attribute('WGS', true::text, NULL, 'red')::text
	       ELSE NULL END;
$$ LANGUAGE SQL stable;


CREATE OR REPLACE FUNCTION is_annotated_flag(v NIAGADS.Variant)
RETURNS text AS $$
	SELECT CASE
	       WHEN v.has_annotation
	       THEN build_icon_attribute(NULL, 'fa-check', 'green', NULL, true::text)::text
	       ELSE NULL END;
$$ LANGUAGE SQL stable;
