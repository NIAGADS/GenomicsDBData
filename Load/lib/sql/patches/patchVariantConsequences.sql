-- patches
-- move `input` from vep_output to `vcf_entry`
-- add index on variant type? or is_sv column (display->variant_type)
-- create most_severe_consequence
-- create ranked_consequence

/*
ALTER TABLE AnnotatedVDB.Variant ADD COLUMN is_structural_variant BOOLEAN;
ALTER TABLE AnnotatedVDB.Variant ADD COLUMN vcf_entry JSONB;
ALTER TABLE AnnotatedVDB.Variant ADD COLUMN most_severe_consequence JSONB;
ALTER TABLE AnnotatedVDB.Variant ADD COLUMN ranked_consequences JSONB;
*/

CREATE SEQUENCE AnnotatedVDB.update_tracker START 1;
UPDATE AnnotatedVDB.Variant_chr22 SET vcf_entry = vep_output->'input' WHERE nextval('update_tracker') != 0;
DROP SEQUENCE update_tracker;

-- to check progress
-- SELECT CURRVAL('update_tracker');
--UPDATE AnnotatedVDB.Variant_chr22 SET vep_output = vep_output - 'input';