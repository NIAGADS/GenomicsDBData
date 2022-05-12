DROP MATERIALIZED VIEW IF EXISTS NIAGADS.PopulationKeys;

CREATE MATERIALIZED VIEW NIAGADS.PopulationKeys AS (
SELECT DISTINCT KEY AS datasource, jsonb_object_keys(VALUE)
FROM AnnotatedVDB.Variant, jsonb_each(allele_frequencies)
WHERE allele_frequencies IS NOT NULL
);


