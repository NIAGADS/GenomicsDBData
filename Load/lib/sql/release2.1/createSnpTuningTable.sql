DROP TABLE SNP CASCADE;
/*
CREATE INDEX seqvar_ind07 ON Results.SeqVariation(p_value ASC, snp_na_feature_id, label);
CREATE INDEX seqvar_ind08 ON Results.SeqVariation(phenotype_id, snp_na_feature_id, label);
*/

CREATE TABLE SNP (
    na_feature_id INTEGER NOT NULL
  , source_id TEXT NOT NULL
  , closest_gene_entrez TEXT
  , allele_frequencies TEXT
  , is_common BOOLEAN
  , has_clinical_significance BOOLEAN
  , chromosome TEXT
  , start_min INTEGER
  , top_snpeff_effect TEXT
  , variant_class_abbrev TEXT
  , major_allele TEXT
  , minor_allele TEXT
  , PRIMARY KEY(source_id)
);

INSERT INTO SNP (
 na_feature_id 
  , source_id
  , closest_gene_entrez
  , allele_frequencies
  , is_common
  , has_clinical_significance 
  , chromosome
  , start_min
  , top_snpeff_effect
  , variant_class_abbrev
  , major_allele
  , minor_allele

)
 (
SELECT * FROM (
WITH Effects AS (
SELECT DISTINCT snp_na_feature_id, label, 
CASE WHEN label = 'LOW' THEN 3
     WHEN label = 'MODERATE' THEN 2
     WHEN label = 'HIGH' THEN 1 END AS effect_rank  
FROM Results.SeqVariation WHERE protocol_app_node_id = 72
), 

maxEffect AS (
  SELECT MAX(effect_rank) AS max_effect_rank, snp_na_feature_id FROM effects GROUP BY snp_na_feature_id
),

snpEff AS (
SELECT snp_na_feature_id,
CASE WHEN max_effect_rank = 1 THEN 'HIGH'
     WHEN max_effect_rank = 2 THEN 'MODERATE'
     WHEN max_effect_rank = 3 THEN 'LOW' END AS top_effect
FROM maxEffect) 

SELECT 
  sf.na_feature_id
, sf.source_id
, (SELECT REPLACE(SPLIT_PART(UNNEST(REGEXP_MATCHES(sf.description, 'GENEINFO=.+?;')), ':', 2),';','')) AS closes
t_gene_entrez
, (SELECT REPLACE(SPLIT_PART(UNNEST(REGEXP_MATCHES(sf.description, 'CAF=.+?;')), '=', 2), ';', '')) AS allele_fr
equencies
, (SELECT SPLIT_PART(UNNEST(REGEXP_MATCHES(sf.description, 'COMMON=\d')), '=', 2))::boolean AS is_common
, (SELECT SPLIT_PART(UNNEST(REGEXP_MATCHES(sf.description, 'CLNSIG=\d')), '=', 2))::boolean AS has_clinical_sign
ificance
, nas.source_id AS chromosome
, nl.start_min
, snpEff.top_effect AS top_snpeff_effect
, sf.name AS variant_class_abbrev
, sf.major_allele
, sf.minor_allele
FROM DoTS.SnpFeature sf
LEFT OUTER JOIN DoTS.NASequence nas
ON sf.na_sequence_id = nas.na_sequence_id
LEFT OUTER JOIN DoTS.NALocation nl
ON sf.na_feature_id = nl.na_feature_id
LEFT OUTER JOIN snpEff
ON snpEff.snp_na_feature_id = sf.na_feature_id
) a);


CREATE UNIQUE INDEX snp_ind06 ON SNP (na_feature_id); 
CREATE INDEX snp_ind07 ON SNP(top_snpeff_effect, source_id); 
CREATE INDEX snp_ind01 ON SNP (closest_gene_entrez, source_id); 
CREATE INDEX snp_ind02 ON SNP (is_common, source_id);
CREATE INDEX snp_ind03 ON SNP(has_clinical_significance, source_id); 
CREATE INDEX snp_ind04 ON SNP(chromosome, start_min ASC, source_id); 
CREATE INDEX snp_ind05 ON SNP(phenotype, start_min ASC, source_id); 

-- grants
GRANT SELECT ON Snp TO genomicsdb;