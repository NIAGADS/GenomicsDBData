DROP MATERIALIZED VIEW IF EXISTS NIAGADS.VariantGWASTopHits CASCADE;

-- note: NIAGADS.DatasetTopHits depends on this view

SET maintenance_work_mem="100GB";
SET max_parallel_maintenance_workers TO 8;

CREATE MATERIALIZED VIEW NIAGADS.VariantGWASTopHits AS (
SELECT r.protocol_app_node_id,
pan.source_id AS dataset_id,
r.variant_record_primary_key,
v.metaseq_id, v.ref_snp_id,
v.chromosome, v.position,
v.location_start, v.location_end,
v.ref_allele, v.alt_allele,
v.display_allele,
v.sequence_allele,
v.variant_class_abbrev,
v.is_adsp_variant,
v.annotation,
r.bin_index,
r.neg_log10_pvalue,
r.pvalue_display,
r.frequency,
r.allele AS test_allele
FROM Results.VariantGWAS r, Study.ProtocolAppNode pan,
NIAGADS.Variant v
WHERE r.protocol_app_node_id = pan.protocol_app_node_id
AND r.neg_log10_pvalue >= 3
AND r.neg_log10_pvalue != 'NaN'
AND pan.source_id NOT ILIKE '%Catalog%'
AND v.record_primary_key = r.variant_record_primary_key
);


GRANT SELECT ON NIAGADS.VariantGWASTopHits TO gus_r, gus_w, comm_wdk_w;



-- cluster
CREATE INDEX TOP_GWAS_VIEW_ORDER ON NIAGADS.VariantGWASTopHits(DATASET_ID, CHROMOSOME, NEG_LOG10_PVALUE DESC);
ALTER MATERIALIZED VIEW NIAGADS.VariantGWASTopHits CLUSTER ON TOPGWAS_VIEW_ORDER;

-- INDEXES
CREATE INDEX TOP_GWAS_VIEW_VRPK ON NIAGADS.VariantGWASTopHits (VARIANT_RECORD_PRIMARY_KEY);

CREATE INDEX TOP_GWAS_VIEW_NL10P ON NIAGADS.VariantGWASTopHits(NEG_LOG10_PVALUE DESC);

CREATE INDEX TOP_GWAS_VIEW_DATASET ON NIAGADS.VariantGWASTopHits USING BRIN(DATASET_ID);

CREATE INDEX TOP_GWAS_VIEW_DATASET_GWS ON NIAGADS.VariantGWASTopHits(DATASET_ID, NEG_LOG10_PVALUE DESC)
       WHERE neg_log10_pvalue >=  (-1 * log(10, 5e-8)); --5e-8

CREATE INDEX TOP_GWAS_VIEW_BIN_INDEX ON NIAGADS.VariantGWASTopHits USING GIST(BIN_INDEX, POSITION);

CREATE INDEX TOP_GWAS_VIEW_PER_TRACK_LOC ON NIAGADS.VariantGWASTopHits(DATASET_ID, CHROMOSOME, POSITION);


