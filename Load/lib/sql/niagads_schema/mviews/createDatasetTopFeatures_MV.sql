
DROP MATERIALIZED VIEW IF EXISTS NIAGADS.DatasetTopFeatures;

CREATE MATERIALIZED VIEW NIAGADS.DatasetTopFeatures AS (
SELECT * FROM (
WITH 
hits AS (
    SELECT track,
'@PROJECT_ID@'::text AS project_id,
variant_record_primary_key AS record_primary_key,
neg_log10_pvalue,
is_adsp_variant,
pvalue_display,
test_allele,
CASE WHEN msc_impacted_gene(annotation->'ADSP_MOST_SEVERE_CONSEQUENCE') IS NOT NULL
THEN msc_impacted_gene(annotation->'ADSP_MOST_SEVERE_CONSEQUENCE')
ELSE 
CASE WHEN ref_snp_id IS NULL 
THEN array_to_string((regexp_split_to_array(metaseq_id, ':'::text))[1:2], ':')
ELSE ref_snp_id END 
END AS hit,

CASE WHEN msc_impacted_gene(annotation->'ADSP_MOST_SEVERE_CONSEQUENCE')  IS NOT NULL
THEN 'gene' ELSE 'variant' END AS hit_type

FROM 
NIAGADS.VariantGWASTopHits),

topHits AS (
SELECT DISTINCT ON (track, hit)
track,
hit,
first_value(hit_type) OVER wnd AS hit_type,
first_value(neg_log10_pvalue) OVER wnd AS neg_log10_pvalue,
first_value(record_primary_key) OVER wnd AS ld_reference_variant
FROM hits
WINDOW wnd AS (
PARTITION BY track, hit ORDER BY neg_log10_pvalue DESC
ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)),

rankedHits AS (
SELECT *, 
RANK() OVER (PARTITION BY track ORDER BY neg_log10_pvalue DESC)
FROM topHits
),

topRankedHits AS (
SELECT h.*, ga.gene_type,
ga.gene_symbol AS hit_display_value,
ga.chromosome, ga.location_start, ga.location_end
FROM rankedHits h, CBIL.GeneAttributes ga
WHERE h.hit = ga.source_id 
AND h.hit_type = 'gene'
AND rank <= 100

UNION ALL

SELECT h.*, NULL AS gene_type,
hit AS hit_display_value,
'chr' || split_part(h.ld_reference_variant, ':', 1) AS chromosome,
split_part(h.ld_reference_variant, ':', 2)::integer AS location_start,
split_part(h.ld_reference_variant, ':', 2)::integer AS location_end
FROM rankedHits h
WHERE h.hit_type = 'variant'
AND rank <= 100)

SELECT *,
RANK() OVER (PARTITION BY track, chromosome ORDER BY neg_log10_pvalue DESC) AS per_chr_rank
FROM topRankedHits) a
);


CREATE INDEX DATASET_TOP_FEATURES_TRACK_IDX ON NIAGADS.DatasetTopFeatures(track);
CREATE INDEX DATASET_TOP_FEATURES_RANK_IDX ON NIAGADS.DatasetTopFeatures(rank);
CREATE INDEX DATASET_TOP_FEATURES_CHR_RANK_IDX ON NIAGADS.DatasetTopFeatures(PER_CHR_RANK);

GRANT SELECT ON NIAGADS.DatasetTopFeatures TO gus_r, gus_w, comm_wdk_w;
