DROP MATERIALIZED VIEW SnpGwasResults_NEW CASCADE;

CREATE MATERIALIZED VIEW SnpGwasResults_NEW AS (
SELECT * FROM (
WITH Results AS (SELECT
         s.source_id
       , s.chromosome
       , s.start_min
		   , sr.p_value AS log_pvalue
		   , sr.categorical_value AS allele
       , ra.resource_id
	 	   , ra.resource_source_id AS track
		   , ra.resource_collection_source_id AS resource_accession
		   , ra.resource_name
		   , ra.description AS resource_description
		   , ra.resource_subtype
		   , s.chromosome || ':' || s.start_min - 20 || '..' || s.start_min + 20 AS span
		   , s.chromosome || ':' || s.start_min || '..' || s.start_min  AS highlight_span
		   , CASE WHEN sr.genetic_location IS NULL THEN s.chromosome || ':' || s.start_min
		     ELSE sr.genetic_location END AS mapped_variant
        , CASE WHEN p_value = 999 THEN '0'
		   WHEN p_value > 300 THEN '1e-'|| p_value::text
		   ELSE to_char((10 ^ (-1 * p_value))::numeric, '99D99EEEE') END AS p_value
      FROM  Results.SegmentResult sr
		   , SNP s
		   , ResourceAttributes ra
       , DoTS.ExternalNaSequence nas
		   WHERE sr.na_sequence_id = nas.na_sequence_id
       AND nas.source_id = s.chromosome
       AND s.start_min = sr.segment_start
		   AND sr.protocol_app_node_id = ra.resource_id
		   AND ra.resource_collection_source_id LIKE 'NG%'
       AND sr.p_value > 0
    ),
    
    RankedResults AS (SELECT *
  , ROW_NUMBER() OVER (PARTITION BY source_id, resource_id ORDER BY log_pvalue DESC) AS row_number
  FROM Results),

  
  SVResults AS (
  	   SELECT 
        s.source_id
       , s.chromosome
       , s.start_min
		   , sv.p_value AS log_pvalue
		   , sv.allele
       , ra.resource_id
		   , ra.resource_source_id AS track
		   , ra.resource_collection_source_id AS resource_accession
		   , ra.resource_name
		   , ra.description AS resource_description
		   , ra.resource_subtype
		   , s.chromosome || ':' || s.start_min - 20 || '..' || s.start_min + 20 AS span
		   , s.chromosome || ':' || s.start_min || '..' || s.start_min  AS highlight_span
		   , NULL::text AS mapped_variant
       , CASE WHEN p_value = 999 THEN '0'
		   WHEN p_value > 300 THEN '1e-'|| p_value::text
		   ELSE to_char((10 ^ (-1 * p_value))::numeric, '99D99EEEE') END AS p_value
		   FROM Results.SeqVariation sv
		   , SNP s
		   , ResourceAttributes ra
		   WHERE s.na_feature_id = sv.snp_na_feature_id
		   AND sv.protocol_app_node_id = ra.resource_id
		   AND ra.resource_collection_source_id LIKE 'NG%'
       AND sv.p_value > 0
   ),
   
  SVRankedResults AS (SELECT *
  , ROW_NUMBER() OVER (PARTITION BY source_id, resource_id ORDER BY log_pvalue DESC) AS row_number
  FROM SVResults)
   
   SELECT 
          source_id
       , chromosome
       , start_min
		   , log_pvalue
		   , allele
       , resource_id
	 	   , track
		   , resource_accession
		   , resource_name
		   , resource_description
		   , resource_subtype
		   , span
		   , highlight_span
		   , mapped_variant::text
        , p_value
  FROM RankedResults WHERE row_number = 1
	   
     
     UNION ALL
     
    SELECT 
          source_id
       , chromosome
       , start_min
		   , log_pvalue
		   , allele
       , resource_id
	 	   , track
		   , resource_accession
		   , resource_name
		   , resource_description
		   , resource_subtype
		   , span
		   , highlight_span
		   , mapped_variant::text
        , p_value
  FROM SVRankedResults WHERE row_number = 1
 
) a);



CREATE INDEX sr_snpmap_new_ind01 ON SnpGwasResults_NEW (source_id);
CREATE INDEX sr_snpmap_new__ind02 ON SnpGwasResults_NEW (source_id, log_pvalue) WHERE log_pvalue >= -1 * log(5 * 10 ^ (-8));
CREATE INDEX sr_snpmap_new_ind03 ON SnpGwasResults_NEW (track);
CREATE INDEX sr_snpmap_new_ind04 ON SnpGwasResults_NEW (chromosome, start_min);
CREATE INDEX sr_snpmap_new_ind06 ON SnpGwasResults_NEW (log_pvalue);
CREATE INDEX sr_snpmap_new_ind06 ON SnpGwasResults_NEW (resource_accession);

GRANT SELECT ON SnpGwasResults_NEW TO GenomicsDB;

