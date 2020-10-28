DROP MATERIALIZED VIEW IF EXISTS NIAGADS.GeneColocatedVariants;

CREATE MATERIALIZED VIEW NIAGADS.GeneColocatedVariants AS
(
    SELECT
        ga.gene_id,
        ga.source_id,
        ga.gene_symbol,
        sf.primary_key AS variant_primary_key,
        sf.na_feature_id AS snp_na_feature_id,
        sf.is_adsp_variant,
        (sf.annotation->>'ADSP_WES')::BOOLEAN AS is_adsp_wes,
        (sf.annotation->>'ADSP_WGS')::BOOLEAN AS is_adsp_wgs,
        sf.name                               AS variant_source,
        CASE
            WHEN sf.position_start > ga.end_max
            THEN 'downstream'
            WHEN sf.position_start < ga.start_min
            THEN 'upstream'
            ELSE 'in gene'
        END     AS relative_position,
        sf.name AS SOURCE
    FROM
        DoTS.SnpFeature sf,
        NIAGADS.GeneAttributes ga
    WHERE
        sf.chromosome = ga.chromosome
    AND sf.position_start BETWEEN ga.start_min - 100000::INT AND ga.end_max + 100000::INT
);

CREATE INDEX NGCV_IND01 ON NIAGADS.GeneColocatedVariants(source_id, relative_position);
CREATE INDEX NGCV_IND02 ON NIAGADS.GeneColocatedVariants(gene_symbol, relative_position);
CREATE INDEX NGCV_IND03 ON NIAGADS.GeneColocatedVariants(gene_id);
CREATE INDEX NGCV_IND01 ON NIAGADS.GeneColocatedVariants(is_adsp);
CREATE INDEX NGCV_IND01 ON NIAGADS.GeneColocatedVariants(source_id, is_adsp);
CREATE INDEX NGCV_IND01 ON NIAGADS.GeneColocatedVariants(gene_symbol, is_adsp);
CREATE INDEX NGCV_IND02 ON NIAGADS.GeneColocatedVariants(relative_position);

GRANT SELECT ON NIAGADS.GeneColocatedVariants TO genomicsdb, gus_r;
