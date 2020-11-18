CREATE OR REPLACE FUNCTION sequence_allele_display(allele TEXT)
RETURNS text AS $$
	SELECT build_text_attribute('[' || allele || ']', NULL, 'red')::text;
$$ LANGUAGE SQL stable;


CREATE OR REPLACE FUNCTION adsp_variant_display_flag(flag BOOLEAN)
RETURNS text AS $$
	SELECT CASE
	       WHEN flag
	       THEN build_icon_attribute('ADSP Variant', 'fa-check-square-o', 'red', NULL, true::text)::text
	       ELSE NULL END;
$$ LANGUAGE SQL stable;


CREATE OR REPLACE FUNCTION adsp_display_badges(recordPK TEXT)
  RETURNS TABLE(adsp_wes_badge JSONB, adsp_wgs_badge JSONB) AS $$
BEGIN
	RETURN QUERY
	SELECT 
	CASE WHEN adsp_qc->'ADSP_WES'->>'FILTER_STATUS' = 'PASS' 
	THEN build_nonlink_badge_attribute('WES', true::text, NULL, 'red')
	ELSE NULL END AS adsp_wes_badge,

	CASE WHEN adsp_qc->'ADSP_WGS'->>'FILTER_STATUS' = 'PASS' 
	THEN build_nonlink_badge_attribute('WGS', true::text, NULL, 'red')
	ELSE NULL END AS adsp_wgs_badge

	FROM get_adsp_qc_by_primary_key(recordPK);
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION adsp_display_badges_niagads(recordPK TEXT)
  RETURNS TABLE(adsp_wes_badge JSONB, adsp_wgs_badge JSONB) AS $$
BEGIN
	RETURN QUERY
	SELECT 
	CASE WHEN annotation->'ADSP_WES'->>'FILTER_STATUS' = 'PASS' 
	THEN build_nonlink_badge_attribute('WES', true::text, NULL, 'red')
	ELSE NULL END AS adsp_wes_badge,

	CASE WHEN annotation->'ADSP_WGS'->>'FILTER_STATUS' = 'PASS' 
	THEN build_nonlink_badge_attribute('WGS', true::text, NULL, 'red')
	ELSE NULL END AS adsp_wgs_badge

	FROM NIAGADS.Variant WHERE record_primary_key = recordPK;
END;

$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION adsp_qc_status_niagads(recordPK TEXT)
  RETURNS TABLE(is_adsp_variant BOOLEAN, is_adsp_wes BOOLEAN, is_adsp_wgs BOOLEAN, 
  wes_filter JSONB, wgs_filter JSONB) AS $$
BEGIN
	RETURN QUERY
	WITH wgs AS (	
	SELECT recordPK AS record_primary_key, jsonb_build_object(
	'text', REPLACE(REPLACE(ot.definition, 'Baylor', 'ATLAS'), 'Broad', 'GATK'),
	'json', CASE WHEN split_part(ot.definition, ':', 1) = 'PASS' 
	THEN build_text_attribute('PASS', split_part(replace(replace(ot.definition, 'Baylor', 'ATLAS'), 'Broad', 'GATK'), ': ', 2), 'blue') 
	WHEN split_part(ot.definition, ':', 1) = 'FAIL' 
	THEN build_text_attribute('FAIL', split_part(replace(replace(ot.definition, 'Baylor', 'ATLAS'), 'Broad', 'GATK'), ': ', 2), 'red') END) 
	AS wgs_filter
	FROM NIAGADS.Variant v, SRes.OntologyTerm ot
	WHERE v.annotation->'ADSP_WGS'->>'FILTER' = ot.name
	AND v.record_primary_key = recordPK),

	wes AS (
	SELECT recordPK AS record_primary_key, jsonb_build_object(
	'text', REPLACE(REPLACE(ot.definition, 'Baylor', 'ATLAS'), 'Broad', 'GATK'),
	'json', CASE WHEN split_part(ot.definition, ':', 1) = 'PASS' 
	THEN build_text_attribute('PASS', split_part(replace(replace(ot.definition, 'Baylor', 'ATLAS'), 'Broad', 'GATK'), ': ', 2), 'blue') 
	WHEN split_part(ot.definition, ':', 1) = 'FAIL' 
	THEN build_text_attribute('FAIL', split_part(replace(replace(ot.definition, 'Baylor', 'ATLAS'), 'Broad', 'GATK'), ': ', 2), 'red') END) 
	AS wes_filter
	FROM NIAGADS.Variant v, SRes.OntologyTerm ot
	WHERE v.annotation->'ADSP_WES'->>'FILTER' = ot.name
	AND v.record_primary_key = recordPK),

	filter_status AS (
	SELECT recordPK AS record_primary_key, wes.wes_filter, wgs.wgs_filter 
	FROM wes LEFT OUTER JOIN wgs ON wes.record_primary_key = wgs.record_primary_key)

	SELECT CASE WHEN v.is_adsp_variant IS NULL THEN FALSE ELSE v.is_adsp_variant END AS is_adsp_variant,
	CASE WHEN annotation->'ADSP_WES'->>'FILTER_STATUS' = 'PASS' 
	THEN TRUE ELSE FALSE END AS is_adsp_wes,
	CASE WHEN annotation->'ADSP_WGS'->>'FILTER_STATUS' = 'PASS' 
	THEN TRUE ELSE FALSE END AS is_adsp_wgs,
	filter_status.wes_filter,
	filter_status.wgs_filter
	FROM NIAGADS.Variant v LEFT OUTER JOIN filter_status 
	ON filter_status.record_primary_key = v.record_primary_key
	WHERE v.record_primary_key = recordPK;
END;


$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION adsp_qc_status(recordPK TEXT)
  RETURNS TABLE(is_adsp_variant BOOLEAN, is_adsp_wes BOOLEAN, is_adsp_wgs BOOLEAN, 
  wes_filter JSONB, wgs_filter JSONB) AS $$
BEGIN
	RETURN QUERY
   	WITH qc AS (SELECT * FROM get_adsp_qc_by_primary_key(recordPK)),

	wgs AS (	
	SELECT recordPK AS record_primary_key, 
	jsonb_build_object('text', REPLACE(REPLACE(ot.definition, 'Baylor', 'ATLAS'), 'Broad', 'GATK'),
	'json', CASE WHEN split_part(ot.definition, ':', 1) = 'PASS' 
	THEN build_text_attribute('PASS', split_part(replace(replace(ot.definition, 'Baylor', 'ATLAS'), 'Broad', 'GATK'), ': ', 2), 'blue') 
	WHEN split_part(ot.definition, ':', 1) = 'FAIL' 
	THEN build_text_attribute('FAIL', split_part(replace(replace(ot.definition, 'Baylor', 'ATLAS'), 'Broad', 'GATK'), ': ', 2), 'red') END) AS wgs_filter
	FROM qc v, SRes.OntologyTerm ot
	WHERE v.adsp_qc->'ADSP_WGS'->>'FILTER' = ot.name
	AND v.record_primary_key = recordPK),

	wes AS (
	SELECT recordPK AS record_primary_key, 
	jsonb_build_object('text', REPLACE(REPLACE(ot.definition, 'Baylor', 'ATLAS'), 'Broad', 'GATK'),
        'json', CASE WHEN split_part(ot.definition, ':', 1) = 'PASS' 
	THEN build_text_attribute('PASS', split_part(replace(replace(ot.definition, 'Baylor', 'ATLAS'), 'Broad', 'GATK'), ': ', 2), 'blue') 
	WHEN split_part(ot.definition, ':', 1) = 'FAIL' 
	THEN build_text_attribute('FAIL', split_part(replace(replace(ot.definition, 'Baylor', 'ATLAS'), 'Broad', 'GATK'), ': ', 2), 'red') END) AS wes_filter
	FROM qc v, SRes.OntologyTerm ot
	WHERE v.adsp_qc->'ADSP_WES'->>'FILTER' = ot.name
	AND v.record_primary_key = recordPK),


	filter_status AS (
	SELECT recordPK AS record_primary_key, wes.wes_filter, wgs.wgs_filter FROM wes LEFT OUTER JOIN wgs ON wes.record_primary_key = wgs.record_primary_key)


	SELECT is_adsp_variant(recordPK),
	CASE WHEN v.adsp_qc->'ADSP_WES'->>'FILTER_STATUS' = 'PASS' 
	THEN TRUE ELSE FALSE END AS is_adsp_wes,
	CASE WHEN v.adsp_qc->'ADSP_WGS'->>'FILTER_STATUS' = 'PASS' 
	THEN TRUE ELSE FALSE END AS is_adsp_wgs,
	filter_status.wes_filter,
	filter_status.wgs_filter

	FROM  qc v LEFT OUTER JOIN filter_status 
	ON filter_status.record_primary_key = v.record_primary_key
	WHERE v.record_primary_key = recordPK;
END;


$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION msc_impacted_transcript(transcriptId TEXT, genomeBuild TEXT)
RETURNS TEXT AS $$
DECLARE mit TEXT;
BEGIN
	SELECT build_link_attribute(transcriptID,
	CASE
		WHEN genomeBuild LIKE 'GRCh37%'
		THEN '+ENSEMBL_TRANSCRIPT_URL_GRCh37+'
		ELSE '+ENSEMBL_TRANSCRIPT_URL_GRCh38+'
		END, NULL, 'view transript details from Ensembl' ||
	CASE
		WHEN genomeBuild LIKE 'GRCh37%'
		THEN ' GRCh37 Archive'
		ELSE ''
	END)::text INTO mit;
	RETURN mit;
END;
$$ LANGUAGE plpgsql;
