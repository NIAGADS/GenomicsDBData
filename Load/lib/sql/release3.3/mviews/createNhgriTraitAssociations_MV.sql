DROP MATERIALIZED VIEW IF EXISTS NIAGADS.NhgriTraitAssociations;

CREATE MATERIALIZED VIEW NIAGADS.NhgriTraitAssociations
AS (
SELECT sv.snp_na_feature_id AS na_feature_id
, sv.variant_primary_key
, sf.source_id
, sv.map AS map_region
, sv.citation AS pubmed_id
, sv.allele
, sv.odds_ratio
, sv.p_value
, sv.phenotype_id
, p.name AS phenotype
, sv.sequence_ontology_id
, replace(so.name, '_', ' ') AS variant_type
FROM Results.SeqVariation sv
, SRes.OntologyTerm so
, SRes.OntologyTerm p
, Study.ProtocolAppNode pan
WHERE sv.protocol_app_node_id = pan.protocol_app_node_id
AND pan.source_id = 'NHGRI_GWAS_CATALOG'
AND so.ontology_term_id = sv.sequence_ontology_id
AND p.ontology_term_id = sv.phenotype_id
);

CREATE INDEX nhgritraitassociations_pk ON NIAGADS.NhgriTraitAssociations((variant_primary_key);
CREATE INDEX nhgritraitassociations_ind0 ON NIAGADS.NhgriTraitAssociations(phenotype_id, variant_primary_key);
CREATE INDEX nhgritraitassociations_ind1 ON NIAGADS.NhgriTraitAssociations(phenotype, variant_primary_key);
CREATE INDEX nhgritraitassociations_ind2 ON NIAGADS.NhgriTraitAssociations(variant_type, variant_primary_key);

GRANT SELECT ON NIAGADS.NhgriTraitAssociations TO genomicsdb;


