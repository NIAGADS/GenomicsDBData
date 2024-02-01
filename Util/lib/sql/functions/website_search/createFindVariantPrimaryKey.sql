-- finds variant by chr:pos:ref:alt id

CREATE OR REPLACE FUNCTION find_variant_primary_key(variantID TEXT)
       RETURNS TEXT AS $$
DECLARE
	recordPK TEXT;
BEGIN

WITH
MatchedVariants AS (
SELECT CASE 
 WHEN LOWER(variantID) LIKE 'rs%' AND LOWER(variantID) NOT LIKE '%:%' THEN 
        (SELECT record_primary_key FROM find_variant_by_refsnp(LOWER(variantID), TRUE))
 WHEN LOWER(variantID) LIKE '%:%' AND LOWER(variantID) NOT LIKE '%_rs%' THEN
        (SELECT record_primary_key AS source_id FROM find_variant_by_metaseq_id_variations(variantID, TRUE))
 WHEN LOWER(variantID) LIKE '%_rs%' AND LOWER(variantID) LIKE '%:%' THEN
        variantID -- assume since it is in our format (chr:pos:ref:alt_refsnp), it is a valid NIAGADS GenomicsDB variant id
 END AS variant_primary_key
)
--SELECT CASE WHEN variant_primary_key IS NULL THEN variantID
--ELSE variant_primary_key END INTO recordPK 
SELECT variant_primary_key INTO recordPK -- need to be able to track no matches
FROM MatchedVariants;

RETURN recordPK;

END;

$$ LANGUAGE plpgsql;


/* NOTE may also need to change functions in ../find_variants/createMapVariantsForLoad.sql to match */

--DROP FUNCTION get_variant_primary_keys(text, boolean);
CREATE OR REPLACE FUNCTION get_variant_primary_keys(variantID TEXT, firstHitOnly BOOLEAN DEFAULT TRUE) 
       RETURNS TABLE(search_term TEXT, variant_primary_key JSONB) AS $$

BEGIN
RETURN QUERY

WITH variant AS (SELECT regexp_split_to_table(variantID, ',') AS id),

MatchedVariants AS (
SELECT variant.id AS search_term,
CASE WHEN LOWER(variant.id) LIKE 'rs%' AND LOWER(variant.id) NOT LIKE '%:%' THEN 
    (SELECT jsonb_agg(record_primary_key) FROM find_variant_by_refsnp(LOWER(variant.id), firstHitOnly))
WHEN LOWER(variant.id) LIKE 'rs%' AND LOWER(variant.id) LIKE '%:%' THEN -- refsnp & alleles
    (SELECT jsonb_agg(record_primary_key) FROM find_variant_by_refsnp_and_alleles(variant.id, firstHitOnly))
WHEN LOWER(variant.id) LIKE '%:%' AND LOWER(variant.id) NOT LIKE '%:rs%' THEN
    (SELECT jsonb_agg(record_primary_key) FROM find_variant_by_metaseq_id_variations(variant.id, firstHitOnly))
WHEN LOWER(variant.id) LIKE '%:rs%' AND LOWER(variant.id) LIKE '%:%' THEN
    jsonb_agg(variant.id) -- assume since it is in our format (chr:pos:ref:alt:refsnp), it is a valid NIAGADS GenomicsDB variant id
END AS mapped_variant
FROM variant GROUP BY variant.id
)


SELECT mv.search_term, mv.mapped_variant 
FROM MatchedVariants mv;

END;

$$ LANGUAGE plpgsql;

DROP FUNCTION get_variant_primary_keys_and_annotations(TEXT, BOOLEAN, BOOLEAN);
CREATE OR REPLACE FUNCTION get_variant_primary_keys_and_annotations(variantID TEXT, firstHitOnly BOOLEAN DEFAULT TRUE, 
    checkAltAlleles BOOLEAN DEFAULT TRUE)
       RETURNS TABLE(mappings TEXT) AS $$

BEGIN
RETURN QUERY
WITH variant AS (SELECT regexp_split_to_table(variantID, ',') AS id),

MatchedVariants AS (
SELECT variant.id AS search_term,
CASE WHEN firstHitOnly THEN -- return a jsonb object
     CASE WHEN LOWER(variant.id) LIKE 'rs%' AND LOWER(variant.id) NOT LIKE '%:%' THEN 
     	  (SELECT row_to_json(find_variant_by_refsnp(LOWER(variant.id), firstHitOnly))::jsonb)
     WHEN LOWER(variant.id) LIKE 'rs%' AND LOWER(variant.id) LIKE '%:%' THEN -- refsnp & alleles
     	  (SELECT row_to_json(find_variant_by_refsnp_and_alleles(variant.id, firstHitOnly))::jsonb)
     WHEN LOWER(variant.id) LIKE '%:%' AND LOWER(variant.id) NOT LIKE '%:rs%' THEN
          (SELECT row_to_json(find_variant_by_metaseq_id_variations(variant.id, firstHitOnly, checkAltAlleles))::jsonb)
     WHEN LOWER(variant.id) LIKE '%:rs%' AND LOWER(variant.id) LIKE '%:%' THEN
          jsonb_build_object('variant_primary_key', variant.id)
	  -- assume since it is in our format (chr:pos:ref:alt:refsnp), it is a valid NIAGADS GenomicsDB variant id
     END
ELSE -- return a jsonb array b/c may have multiple hits
     CASE WHEN LOWER(variant.id) LIKE 'rs%' AND LOWER(variant.id) NOT LIKE '%:%' THEN
     	  (SELECT json_agg(r)::jsonb FROM (SELECT * FROM find_variant_by_refsnp(LOWER(variant.id), firstHitOnly)) AS r)
     WHEN LOWER(variant.id) LIKE 'rs%' AND LOWER(variant.id) LIKE '%:%' THEN -- refsnp & alleles
      	  (SELECT json_agg(r)::jsonb FROM (SELECT * FROM find_variant_by_refsnp_and_alleles(variant.id, firstHitOnly)) AS r)
     WHEN LOWER(variant.id) LIKE '%:%' AND LOWER(variant.id) NOT LIKE '%:rs%' THEN
	(SELECT json_agg(r)::jsonb FROM (SELECT * FROM find_variant_by_metaseq_id_variations(variant.id, firstHitOnly, checkAltAlleles)) AS r)
     WHEN LOWER(variant.id) LIKE '%:rs%' AND LOWER(variant.id) LIKE '%:%' THEN
           jsonb_agg(jsonb_build_object('variant_primary_key', variant.id))
	   -- assume since it is in our format (chr:pos:ref:alt:refsnp), it is a valid NIAGADS GenomicsDB variant id
     END
END AS mapped_variant
FROM variant GROUP BY variant.id
)

SELECT jsonb_object_agg(mv.search_term, mv.mapped_variant)::TEXT
FROM MatchedVariants mv;

END;

$$ LANGUAGE plpgsql;


DROP FUNCTION get_variant_primary_keys_and_annotations_tbl(text,boolean);
CREATE OR REPLACE FUNCTION get_variant_primary_keys_and_annotations_tbl(variantID TEXT,
    firstHitOnly BOOLEAN DEFAULT TRUE, checkAltAlleles BOOLEAN DEFAULT TRUE)
       RETURNS TABLE(lookup_variant_id TEXT, mapping JSONB) AS $$

BEGIN
RETURN QUERY
WITH variant AS (SELECT regexp_split_to_table(variantID, ',') AS id),

MatchedVariants AS (
SELECT variant.id AS search_term,
CASE WHEN firstHitOnly THEN -- return a jsonb object
     CASE WHEN LOWER(variant.id) LIKE 'rs%' AND LOWER(variant.id) NOT LIKE '%:%' THEN 
     	  (SELECT row_to_json(find_variant_by_refsnp(LOWER(variant.id), firstHitOnly))::jsonb)
     WHEN LOWER(variant.id) LIKE 'rs%' AND LOWER(variant.id) LIKE '%:%' THEN -- refsnp & alleles
     	  (SELECT row_to_json(find_variant_by_refsnp_and_alleles(variant.id, firstHitOnly))::jsonb)
     WHEN LOWER(variant.id) LIKE '%:%' AND LOWER(variant.id) NOT LIKE '%:rs%' THEN
          (SELECT row_to_json(find_variant_by_metaseq_id_variations(variant.id, firstHitOnly, checkAltAlleles))::jsonb)
     WHEN LOWER(variant.id) LIKE '%:rs%' AND LOWER(variant.id) LIKE '%:%' THEN
          jsonb_build_object('variant_primary_key', variant.id)
	  -- assume since it is in our format (chr:pos:ref:alt:refsnp), it is a valid NIAGADS GenomicsDB variant id
     END
ELSE -- return a jsonb array b/c may have multiple hits
     CASE WHEN LOWER(variant.id) LIKE 'rs%' AND LOWER(variant.id) NOT LIKE '%:%' THEN
     	  (SELECT json_agg(r)::jsonb FROM (SELECT * FROM find_variant_by_refsnp(LOWER(variant.id), firstHitOnly)) AS r)
     WHEN LOWER(variant.id) LIKE 'rs%' AND LOWER(variant.id) LIKE '%:%' THEN -- refsnp & alleles
      	  (SELECT json_agg(r)::jsonb FROM (SELECT * FROM find_variant_by_refsnp_and_alleles(variant.id, firstHitOnly)) AS r)
     WHEN LOWER(variant.id) LIKE '%:%' AND LOWER(variant.id) NOT LIKE '%:rs%' THEN
	(SELECT json_agg(r)::jsonb FROM (SELECT * FROM find_variant_by_metaseq_id_variations(variant.id, firstHitOnly, checkAltAlleles)) AS r)
     WHEN LOWER(variant.id) LIKE '%:rs%' AND LOWER(variant.id) LIKE '%:%' THEN
           jsonb_agg(jsonb_build_object('variant_primary_key', variant.id))::jsonb
	   -- assume since it is in our format (chr:pos:ref:alt:refsnp), it is a valid NIAGADS GenomicsDB variant id
     END
END AS mapped_variant
FROM variant GROUP BY variant.id
)

SELECT mv.search_term, mv.mapped_variant::JSONB - 'bin_index'
FROM MatchedVariants mv;

END;

$$ LANGUAGE plpgsql;


CREATE EXTENSION IF NOT EXISTS plperl;
--extracts types of lookup variant ids from a list
-- refsnps, refsnps with alleles, metaseq_ids, genomicsdb_pk

-- drop type variantIdlist cascade;
DROP TYPE IF EXISTS VARIANT_ID_LIST CASCADE;
CREATE TYPE VARIANT_ID_LIST AS (rs TEXT, rs_a TEXT, metaseq TEXT, pk TEXT);

-- DROP FUNCTION split_variant_identifer_list_by_types(TEXT)
CREATE OR REPLACE FUNCTION split_variant_identifer_list_by_types(TEXT) 
RETURNS VARIANT_ID_LIST AS $$
    my ($variantStr, $idType) = @_;

    my @ids = split /,/, $variantStr;
    my @rs; 
    my @rs_a; 
    my @meta;
    my @pk;

    foreach my $id (@ids) {
       if ($id =~ m/^rs/i && $id !~ m/:/) {
              push(@rs, $id);
       }
       elsif ($id =~ m/^rs/i && $id =~ m/:/) {
              push(@rs_a, $id);
       }
       elsif ($id =~ m/:/ && $id !~ m/:rs/) {
              push(@meta, $id);
       }
       elsif ($id =~ m/:rs/) {
              push(@pk, $id);
       }

    }

    return {rs => join(',',@rs),  rs_a => join(',', @rs_a), metaseq => join(',', @meta), pk => join(',', @pk)}


$$ LANGUAGE plperl;
