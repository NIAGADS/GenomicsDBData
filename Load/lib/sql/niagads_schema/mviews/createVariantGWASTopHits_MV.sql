SET maintenance_work_mem="100GB";
SET max_parallel_maintenance_workers TO 8;

DROP MATERIALIZED VIEW IF EXISTS NIAGADS.VariantGWASTopHits CASCADE;

-- note: NIAGADS.DatasetTopHits depends on this view

CREATE MATERIALIZED VIEW NIAGADS.VariantGWASTopHits AS (
SELECT 
row_number() over (order by pan.source_id ASC, v.metaseq_id ASC, r.neg_log10_pvalue DESC) AS variant_gwas_top_hits_id, -- required by SQLAlchemy for API
r.protocol_app_node_id,
pan.source_id AS track,
r.variant_record_primary_key,
v.metaseq_id, v.ref_snp_id,
v.chromosome, v.position,
v.display_attributes,
v.is_adsp_variant,

jsonb_build_object('cadd_scores', v.cadd_scores, 'adsp_most_severe_consequence', 
v.adsp_most_severe_consequence, 'allele_frequencies', 
allele_frequencies /*, 'ADSP_QC_STATUS', adsp_qc->'STATUS'*/) AS annotation,

r.bin_index,
r.neg_log10_pvalue,
r.pvalue_display,
r.frequency,
r.allele AS test_allele,
r.restricted_stats
FROM Results.VariantGWAS r, Study.ProtocolAppNode pan,
AnnotatedVDB.Variant v
WHERE r.protocol_app_node_id = pan.protocol_app_node_id
AND r.neg_log10_pvalue >= 3
AND r.neg_log10_pvalue != 'NaN'
--AND pan.source_id NOT ILIKE '%Catalog%'
AND v.record_primary_key = r.variant_record_primary_key
AND length(v.metaseq_id) < 50 -- indels and snvs only for now
);


GRANT SELECT ON NIAGADS.VariantGWASTopHits TO gus_r, gus_w, comm_wdk_w;



-- cluster
CREATE INDEX TOP_GWAS_VIEW_ORDER ON NIAGADS.VariantGWASTopHits(variant_gwas_top_hits_id);
ALTER MATERIALIZED VIEW NIAGADS.VariantGWASTopHits CLUSTER ON TOP_GWAS_VIEW_ORDER;

-- INDEXES
CREATE INDEX TOP_GWAS_VIEW_VRPK ON NIAGADS.VariantGWASTopHits (METASEQ_ID);
CREATE INDEX TOP_GWAS_VIEW_RSID ON NIAGADS.VariantGWASTopHits (REF_SNP_ID);

CREATE INDEX TOP_GWAS_VIEW_NL10P ON NIAGADS.VariantGWASTopHits(NEG_LOG10_PVALUE DESC);

CREATE INDEX TOP_GWAS_VIEW_DATASET_GWS ON NIAGADS.VariantGWASTopHits(TRACK, NEG_LOG10_PVALUE DESC)
       WHERE neg_log10_pvalue >=  (-1 * log(10, 5e-8)); --5e-8

CREATE INDEX TOP_GWAS_VIEW_BIN_INDEX ON NIAGADS.VariantGWASTopHits USING GIST(BIN_INDEX, POSITION);

CREATE INDEX TOP_GWAS_VIEW_PER_TRACK_LOC ON NIAGADS.VariantGWASTopHits(TRACK, CHROMOSOME, POSITION);


