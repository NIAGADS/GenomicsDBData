DROP MATERIALIZED VIEW IF EXISTS NIAGADS.GeneGwasSummary;

CREATE MATERIALIZED VIEW NIAGADS.GeneGwasSummary AS (
 SELECT ga.source_id, 
 ga.gene_symbol,
 sv.snp_na_feature_id,
 sv.variant_primary_key,
 sv.allele,     
 sv.p_value,
 sv.pvalue_mant,
 sv.pvalue_exp,
 sv.evidence,
 ta.track,
 sv.phenotype_id,
 CASE WHEN split_part(sv.variant_primary_key, ':', 2)::INT < ga.start_min THEN 'upstream'
 WHEN split_part(sv.variant_primary_key, ':', 2)::INT > ga.end_max THEN 'downstream'
 ELSE 'in gene' END AS relative_position
 FROM Results.SeqVariation sv,
 NIAGADS.GeneAttributes ga,
 NIAGADS.TrackAttributes ta
 WHERE split_part(sv.variant_primary_key, ':', 2)::INT BETWEEN ga.start_min - 100000::INT AND ga.end_max + 100000::INT
 AND 'chr' || split_part(sv.variant_primary_key, ':', 1) = ga.chromosome
 AND ta.protocol_app_node_id = sv.protocol_app_node_id
 AND ta.track LIKE 'NG%' 
 AND ta.name NOT LIKE '%exome array%'
 AND sv.p_value >= 7.301029996

 UNION ALL

 SELECT ga.source_id, 
 ga.gene_symbol,
 sv.snp_na_feature_id,
 sv.variant_primary_key,
 sv.allele,     
 sv.p_value,
 sv.pvalue_mant,
 sv.pvalue_exp,
 sv.evidence,
 ta.track,
 sv.phenotype_id,
 CASE WHEN split_part(sv.variant_primary_key, ':', 2)::INT < ga.start_min THEN 'upstream'
 WHEN split_part(sv.variant_primary_key, ':', 2)::INT > ga.end_max THEN 'downstream'
 ELSE 'in gene' END AS relative_position
 FROM Results.SeqVariation sv,
 NIAGADS.GeneAttributes ga,
 NIAGADS.TrackAttributes ta
 WHERE split_part(sv.variant_primary_key, ':', 2)::INT BETWEEN ga.start_min - 100000::INT AND ga.end_max + 100000::INT
 AND 'chr' || split_part(sv.variant_primary_key, ':', 1) = ga.chromosome
 AND ta.protocol_app_node_id = sv.protocol_app_node_id
 AND ta.track LIKE 'NG%' 
 AND ta.name LIKE '%exome array%'
 AND sv.p_value >= 3 
 
 UNION ALL

SELECT ga.source_id, 
 ga.gene_symbol,
 sv.snp_na_feature_id,
 sv.variant_primary_key,
 sv.allele,     
 sv.p_value,
 sv.pvalue_mant,
 sv.pvalue_exp,
 sv.evidence,
 ta.track,
 sv.phenotype_id,
 CASE WHEN split_part(sv.variant_primary_key, ':', 2)::INT < ga.start_min THEN 'upstream'
 WHEN split_part(sv.variant_primary_key, ':', 2)::INT > ga.end_max THEN 'downstream'
 ELSE 'in gene' END AS relative_position
 FROM Results.SeqVariation sv,
 NIAGADS.GeneAttributes ga,
 NIAGADS.TrackAttributes ta
 WHERE split_part(sv.variant_primary_key, ':', 2)::INT BETWEEN ga.start_min - 100000::INT AND ga.end_max + 100000::INT
 AND 'chr' || split_part(sv.variant_primary_key, ':', 1) = ga.chromosome
 AND ta.protocol_app_node_id = sv.protocol_app_node_id
 AND ta.track = 'NHGRI_GWAS_CATALOG'
);

CREATE INDEX IND_GeneGwasSummary_IND01 ON NIAGADS.GeneGwasSummary(source_id);
CREATE INDEX IND_GeneGwasSummary_IND02 ON NIAGADS.GeneGwasSummary(variant_primary_key);
CREATE INDEX IND_GeneGwasSummary_IND03 ON NIAGADS.GeneGwasSummary(snp_na_feature_id);
CREATE INDEX IND_GeneGwasSummary_IND04 ON NIAGADS.GeneGwasSummary(gene_symbol);
CREATE INDEX IND_GeneGwasSummary_IND05 ON NIAGADS.GeneGwasSummary(track);


GRANT SELECT ON NIAGADS.GeneGwasSummary TO genomicsdb;
