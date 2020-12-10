CREATE OR REPLACE FUNCTION record_primary_key(v AnnotatedVDB.Variant)
RETURNS TEXT AS $$
	SELECT CASE WHEN LENGTH(v.metaseq_id) > 350 THEN LEFT(v.metaseq_id, 347) || '...' ELSE v.metaseq_id END 
	|| COALESCE('_' || v.ref_snp_id, '') 
$$ LANGUAGE SQL stable;

CREATE OR REPLACE FUNCTION dbsnp_build(v AnnotatedVDB.Variant)
RETURNS   INTEGER AS $$
	SELECT (v.vep_output->'input'->'info'->'dbSNPBuildID')::integer
$$ LANGUAGE SQL stable;

CREATE OR REPLACE FUNCTION has_genomicsdb_annotation(v AnnotatedVDB.Variant)
RETURNS BOOLEAN AS $$
	SELECT v.other_annotation->'GenomicsDB' IS NOT NULL
$$ LANGUAGE SQL stable;

CREATE OR REPLACE FUNCTION dbsnp_build(v AnnotatedVDB.Variant)
RETURNS INTEGER AS $$
	SELECT (v.vep_output->'input'->'info'->'dbSNPBuildID')::integer
$$ LANGUAGE SQL stable;

CREATE OR REPLACE FUNCTION variant_class_abbrev(v AnnotatedVDB.Variant) 
RETURNS TEXT AS $$
	SELECT v.vep_output->>'variant_class'
$$ LANGUAGE SQL stable;


CREATE OR REPLACE FUNCTION adsp_ms_consequence(v AnnotatedVDB.Variant) 
RETURNS TEXT AS $$
	SELECT DISTINCT replace(array_to_string(json_array_cast_to_text((v.adsp_most_severe_consequence->'consequence_terms')::json), ','), '_', ' ')  

$$ LANGUAGE SQL stable;
