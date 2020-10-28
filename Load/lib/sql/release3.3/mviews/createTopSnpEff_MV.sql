DROP MATERIALIZED VIEW IF EXISTS NIAGADS.TopSnpEffEffect;

CREATE MATERIALIZED VIEW NIAGADS.TopSnpEffEffect AS (
   
    WITH top AS (
       SELECT pve.na_feature_id,
       pve.effect_impact,
       pve.consequence,
       pve.gene_source_id,
       ga.gene_symbol,
       r.rank,
       r.impact
       FROM NIAGADS.PredictedVariantEffect pve,
       NIAGADS.GeneAttributes ga,
       Study.ProtocolAppNode pan,
       NIAGADS.VariantEffectRank r
       WHERE ga.source_id = pve.gene_source_id
       --AND pve.is_most_severe_consequence
       AND pan.source_id = 'SNPEFF' 
       AND pve.protocol_app_node_id = pan.protocol_app_node_id
       AND r.consequence = pve.consequence
       )
    SELECT DISTINCT ON (na_feature_id)
    na_feature_id,
    first_value(consequence) OVER wnd AS top_consequence,
    first_value(gene_source_id) OVER wnd AS gene_source_id,
    first_value(gene_symbol) OVER wnd AS gene_symbol,
    first_value(rank) OVER wnd AS top_rank,
    first_value(effect_impact) OVER wnd AS top_effect_impact
    FROM top
    WINDOW wnd AS (
        PARTITION BY na_feature_id ORDER BY rank, idx(array['HIGH', 'MODERATE', 'LOW', 'MODIFIER'], impact)
	ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) 	
);

CREATE INDEX TSEE_IND01 ON NIAGADS.TopSnpEffEffect(na_feature_id);
CREATE INDEX TSEE_IND02 ON NIAGADS.TopSnpEffEffect(top_effect_impact);
CREATE INDEX TSEE_IND03 ON NIAGADS.TopSnpEffEffect(gene_source_id);
CREATE INDEX TSEE_IND04 ON NIAGADS.TopSnpEffEffect(top_consequence);

GRANT SELECT ON NIAGADS.TopSnpEffEffect TO genomicsdb;
