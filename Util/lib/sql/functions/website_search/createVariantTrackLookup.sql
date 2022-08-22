
CREATE OR REPLACE FUNCTION get_dbsnp_variants(chrm TEXT, locStart INTEGER, locEnd INTEGER)
       RETURNS jSONB AS $$

DECLARE binIndex LTREE;
DECLARE trackInfo JSONB;
BEGIN
	SELECT find_bin_index(chrm, locStart, locEnd) INTO binIndex;
	WITH vcfRows AS (
	SELECT jsonb_build_object(
	'chrom', chromosome,
	'pos', position,
	'id', v.record_primary_key,
	'ref', split_part(metaseq_id, ':', 3),
	'alt', split_part(metaseq_id, ':', 4),
	'qual', '.'::text,
	'filter', (cadd_scores->>'CADD_phred')::numeric,
	'info', 'record=' || v.record_primary_key || ';consequence=' || most_severe_consequence(v.adsp_most_severe_consequence) || ';impact=' || (v.adsp_most_severe_consequence->>'impact')::text
) AS row_json	
  FROM AnnotatedVDB.Variant v
  WHERE binIndex @> v.bin_index
  AND int4range(locStart, locEnd, '[]') @> v.position
  AND v.chromosome = chrm
  AND v.ref_snp_id IS NOT NULL)
    SELECT jsonb_agg(row_json) AS RESULT FROM vcfRows INTO trackInfo;
   RETURN trackInfo;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_dbsnp_common_variants(chrm TEXT, locStart INTEGER, locEnd INTEGER)
       RETURNS JSONB AS $$

DECLARE binIndex LTREE;
DECLARE trackInfo JSONB;
BEGIN
	SELECT find_bin_index(chrm, locStart, locEnd) INTO binIndex;
	WITH vcfRows AS (
	SELECT jsonb_build_object(
	'chrom', chromosome,
	'pos', position,
	'id', v.record_primary_key,
	'ref', split_part(metaseq_id, ':', 3),
	'alt', split_part(metaseq_id, ':', 4),
	'qual', '.'::text,
	'filter', (cadd_scores->>'CADD_phred')::numeric,
	'info', 'record=' || v.record_primary_key || ';consequence=' || most_severe_consequence(v.adsp_most_severe_consequence) || ';impact=' || (v.adsp_most_severe_consequence->>'impact')::text
) AS row_json	
  FROM AnnotatedVDB.Variant v
  WHERE binIndex @> v.bin_index
  AND int4range(locStart, locEnd, '[]') @> v.position
  AND v.chromosome = chrm
  AND v.ref_snp_id IS NOT NULL
  AND (vep_output->'input'->'info'->'COMMON')::integer::boolean)
  SELECT jsonb_agg(row_json) AS RESULT FROM vcfRows INTO trackInfo;

RETURN trackInfo;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION get_adsp_variants(chrm TEXT, locStart INTEGER, locEnd INTEGER)
       RETURNS JSONB AS $$

DECLARE binIndex LTREE;
DECLARE trackInfo JSONB;
BEGIN
	SELECT find_bin_index(chrm, locStart, locEnd) INTO binIndex;
	WITH vcfRows AS (
	SELECT jsonb_build_object(
	'chrom', chromosome,
	'pos', position,
	'id', v.record_primary_key,
	'ref', split_part(metaseq_id, ':', 3),
	'alt', split_part(metaseq_id, ':', 4),
	'qual', '.'::text,
	'filter', (cadd_scores->>'CADD_phred')::numeric,
	'info', 'record=' || v.record_primary_key || ';consequence=' || most_severe_consequence(v.adsp_most_severe_consequence) || ';impact=' || (v.adsp_most_severe_consequence->>'impact')::text
) AS row_json	
  FROM AnnotatedVDB.Variant v
  WHERE binIndex @> v.bin_index
  AND int4range(locStart, locEnd, '[]') @> v.position
  AND v.chromosome = chrm
  AND is_adsp_variant)
SELECT jsonb_agg(row_json) AS RESULT FROM vcfRows INTO trackInfo;

RETURN trackInfo;
END;
$$ LANGUAGE plpgsql;


