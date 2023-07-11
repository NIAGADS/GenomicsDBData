DROP MATERIALIZED VIEW IF EXISTS NIAGADS.ADVP;

CREATE MATERIALIZED VIEW NIAGADS.ADVP AS (
    SELECT variant_gwas_id, r.variant_record_primary_key, 
    r.bin_index, 
    r.neg_log10_pvalue, r.pvalue_display, r.frequency, 
    v.metaseq_id,
    v.ref_snp_id,
    v.chromosome,
    v."position",
    v.display_attributes,
    v.is_adsp_variant,
    jsonb_build_object('CADD_SCORES', v.cadd_scores, 'ADSP_MOST_SEVERE_CONSEQUENCE',
    v.adsp_most_severe_consequence, 'ALLELE_FREQUENCIES', v.allele_frequencies) AS annotation,
    r.restricted_stats,
    CASE WHEN r.allele = 'N' THEN '?' ELSE r.allele END AS test_allele,
    r.restricted_stats->>'Population' AS population,
    r.restricted_stats->>'Pubmed PMID' AS pubmed_id,
    CASE WHEN r.restricted_stats->>'Phenotype' = 'LOAD' THEN 'AD' ELSE  r.restricted_stats->>'Phenotype'  END AS phenotype
    FROM Results.VariantGWAS r, Study.ProtocolAppNode pan,  AnnotatedVDB.Variant v
    WHERE r.protocol_app_node_id = pan.protocol_app_node_id
    AND pan.source_id = 'ADVP'
    AND v.record_primary_key = r.variant_record_primary_key
);

GRANT SELECT ON NIAGADS.DataDictionaryTerms TO comm_wdk_w, genomicsdb_api;

-- cluster
CREATE INDEX ADVP_VIEW_ORDER ON NIAGADS.ADVP(CHROMOSOME, NEG_LOG10_PVALUE DESC);
ALTER MATERIALIZED VIEW NIAGADS.ADVP CLUSTER ON ADVP_VIEW_ORDER;

-- INDEXES
CREATE INDEX ADVP_VIEW_VRPK ON NIAGADS.ADVP (VARIANT_RECORD_PRIMARY_KEY);
CREATE INDEX ADVP_VIEW_REF_SNP ON NIAGADS.ADVP (REF_SNP_ID);

CREATE INDEX ADVP_VIEW_NL10P ON NIAGADS.ADVP(NEG_LOG10_PVALUE DESC);

CREATE INDEX ADVP_VIEW_PHENOTYPE ON NIAGADS.ADVP(PHENOTYPE);
CREATE INDEX ADVP_VIEW_POPULATION ON NIAGADS.ADVP(POPULATION);

CREATE INDEX ADVP_VIEW_GWS ON NIAGADS.ADVP(NEG_LOG10_PVALUE DESC)
       WHERE neg_log10_pvalue >=  (-1 * log(10, 5e-8)); --5e-8

CREATE INDEX ADVP_VIEW_BIN_INDEX ON NIAGADS.ADVP USING GIST(BIN_INDEX, POSITION);

CREATE INDEX ADVP_VIEW_LOC ON NIAGADS.ADVP(CHROMOSOME, POSITION);


