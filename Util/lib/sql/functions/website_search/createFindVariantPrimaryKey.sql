-- finds variant by chr:pos:ref:alt id

DROP FUNCTION find_variants_by_range(text,bigint,bigint);
CREATE OR REPLACE FUNCTION find_variants_by_range(chrm TEXT, locStart BIGINT, locEnd BIGINT)
    RETURNS TABLE(variant_id TEXT, annotation JSONB) AS $$

DECLARE 
    binIndex LTREE;
BEGIN
    SELECT find_bin_index(chrm, locStart, locEnd) INTO binIndex;

    RETURN QUERY
    SELECT t.variant_id, row_to_json(t)::jsonb FROM (
    SELECT v.metaseq_id AS variant_id, v.ref_snp_id,
    v.display_attributes->>'display_allele' AS alleles,
	v.display_attributes->>'variant_class_abbrev' AS variant_class,
    v.chromosome,
    v.position,
    -- (v.display_attributes->>'location_end')::int - (v.display_attributes->>'location_start')::int AS length,
	CASE WHEN v.is_adsp_variant THEN TRUE ELSE FALSE END AS is_adsp_variant, v.bin_index,
	get_variant_annotation_summary(row_to_json(v)::jsonb) AS annotation
    
    FROM AnnotatedVDB.Variant v
    WHERE v.chromosome = chrm
    AND v.bin_index @> binIndex
    AND int8range(locStart,locEnd, '[]') 
    && int8range((v.display_attributes->>'location_start')::int, (v.display_attributes->>'location_end')::int, '[]')) t;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION find_variant_primary_key(variantID TEXT)
       RETURNS TEXT AS $$
DECLARE
	recordPK TEXT;
BEGIN

WITH
MatchedVariants AS (
SELECT CASE 
 WHEN LOWER(variantID) LIKE 'rs%'  THEN 
        (SELECT metaseq_id FROM find_variant_by_refsnp(LOWER(variantID), TRUE))
 WHEN LOWER(variantID) LIKE '%:%' THEN
        (SELECT metaseq_id FROM find_variant_by_metaseq_id_variations(variantID, TRUE))
 WHEN UPPER(variantID) LIKE '%_CHR%' THEN -- structural
    (SELECT metaseq_id FROM AnnotatedVDB.Variant WHERE metaseq_id = variantID) 
 END AS variant_primary_key
)
--SELECT CASE WHEN variant_primary_key IS NULL THEN variantID
--ELSE variant_primary_key END INTO recordPK 
SELECT variant_primary_key INTO recordPK -- need to be able to track no matches
FROM MatchedVariants;

RETURN recordPK;

END;

$$ LANGUAGE plpgsql;


--FIXME: bulk lookups

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
    (SELECT jsonb_agg(av.record_primary_key) FROM AnnotatedVDB.Variant av, variant WHERE record_primary_key = variant.id) -- assume since it is in our format (chr:pos:ref:alt:refsnp), it is a valid NIAGADS GenomicsDB variant id
WHEN UPPER(variant.id) LIKE '%_CHR%' AND variant.id NOT LIKE '%:%' THEN -- structural
    (SELECT jsonb_agg(av.record_primary_key) FROM AnnotatedVDB.Variant av, variant WHERE record_primary_key = variant.id) 
END AS mapped_variant
FROM variant GROUP BY variant.id
)


SELECT mv.search_term, mv.mapped_variant 
FROM MatchedVariants mv;

END;

$$ LANGUAGE plpgsql;

--DROP FUNCTION get_variant_primary_keys_and_annotations(TEXT, BOOLEAN, BOOLEAN, BOOLEAN);
CREATE OR REPLACE FUNCTION get_variant_primary_keys_and_annotations(variantID TEXT, firstHitOnly BOOLEAN DEFAULT TRUE, 
    checkAltAlleles BOOLEAN DEFAULT TRUE, checkNormalizedAlleles BOOLEAN DEFAULT FALSE)
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
          (SELECT row_to_json(find_variant_by_metaseq_id_variations(variant.id, firstHitOnly, checkAltAlleles, checkNormalizedAlleles))::jsonb)
     WHEN LOWER(variant.id) LIKE '%:rs%' AND LOWER(variant.id) LIKE '%:%' THEN
     	  -- assume since it is in our format (chr:pos:ref:alt:refsnp), it is a valid NIAGADS GenomicsDB variant id
          jsonb_build_object('variant_primary_key', variant.id)
    WHEN UPPER(variant.id) LIKE '%_CHR%' AND variant.id NOT LIKE '%:%' THEN -- structural
          jsonb_build_object('variant_primary_key', variant.id)
     END
ELSE -- return a jsonb array b/c may have multiple hits
     CASE WHEN LOWER(variant.id) LIKE 'rs%' AND LOWER(variant.id) NOT LIKE '%:%' THEN
     	  (SELECT json_agg(r)::jsonb FROM (SELECT * FROM find_variant_by_refsnp(LOWER(variant.id), firstHitOnly)) AS r)
     WHEN LOWER(variant.id) LIKE 'rs%' AND LOWER(variant.id) LIKE '%:%' THEN -- refsnp & alleles
      	  (SELECT json_agg(r)::jsonb FROM (SELECT * FROM find_variant_by_refsnp_and_alleles(variant.id, firstHitOnly)) AS r)
     WHEN LOWER(variant.id) LIKE '%:%' AND LOWER(variant.id) NOT LIKE '%:rs%' THEN
	(SELECT json_agg(r)::jsonb FROM (SELECT * FROM find_variant_by_metaseq_id_variations(variant.id, firstHitOnly, checkAltAlleles, checkNormalizedAlleles)) AS r)
     WHEN LOWER(variant.id) LIKE '%:rs%' AND LOWER(variant.id) LIKE '%:%' THEN
     	   -- assume since it is in our format (chr:pos:ref:alt:refsnp), it is a valid NIAGADS GenomicsDB variant id
           jsonb_agg(jsonb_build_object('variant_primary_key', variant.id))
     WHEN UPPER(variant.id) LIKE '%_CHR%' AND variant.id NOT LIKE '%:%' THEN -- structural
        jsonb_agg(jsonb_build_object('variant_primary_key', variant.id))

     END
END AS mapped_variant
FROM variant GROUP BY variant.id
)

SELECT jsonb_object_agg(mv.search_term, mv.mapped_variant)::TEXT
FROM MatchedVariants mv;

END;

$$ LANGUAGE plpgsql;


DROP FUNCTION get_variant_primary_keys_and_annotations_tbl(text,boolean, boolean, boolean);
CREATE OR REPLACE FUNCTION get_variant_primary_keys_and_annotations_tbl(variantID TEXT,
    firstHitOnly BOOLEAN DEFAULT TRUE, checkAltAlleles BOOLEAN DEFAULT TRUE,checkNormalizedAlleles BOOLEAN DEFAULT FALSE)
       RETURNS TABLE(lookup_variant_id TEXT, annotation JSONB) AS $$

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
          (SELECT row_to_json(find_variant_by_metaseq_id_variations(variant.id, firstHitOnly, checkAltAlleles, checkNormalizedAlleles))::jsonb)
     WHEN LOWER(variant.id) LIKE '%:rs%' AND LOWER(variant.id) LIKE '%:%' THEN
          jsonb_build_object('variant_primary_key', variant.id)
	  -- assume since it is in our format (chr:pos:ref:alt:refsnp), it is a valid NIAGADS GenomicsDB variant id
        WHEN UPPER(variant.id) LIKE '%_CHR%' AND variant.id NOT LIKE '%:%' THEN -- structural
          jsonb_build_object('variant_primary_key', variant.id)
     END
ELSE -- return a jsonb array b/c may have multiple hits
     CASE WHEN LOWER(variant.id) LIKE 'rs%' AND LOWER(variant.id) NOT LIKE '%:%' THEN
     	  (SELECT json_agg(r)::jsonb FROM (SELECT * FROM find_variant_by_refsnp(LOWER(variant.id), firstHitOnly)) AS r)
     WHEN LOWER(variant.id) LIKE 'rs%' AND LOWER(variant.id) LIKE '%:%' THEN -- refsnp & alleles
      	  (SELECT json_agg(r)::jsonb FROM (SELECT * FROM find_variant_by_refsnp_and_alleles(variant.id, firstHitOnly)) AS r)
     WHEN LOWER(variant.id) LIKE '%:%' AND LOWER(variant.id) NOT LIKE '%:rs%' THEN
	(SELECT json_agg(r)::jsonb FROM (SELECT * FROM find_variant_by_metaseq_id_variations(variant.id, firstHitOnly, checkAltAlleles, checkNormalizedAlleles)) AS r)
     WHEN LOWER(variant.id) LIKE '%:rs%' AND LOWER(variant.id) LIKE '%:%' THEN
           jsonb_agg(jsonb_build_object('variant_primary_key', variant.id))::jsonb
	   -- assume since it is in our format (chr:pos:ref:alt:refsnp), it is a valid NIAGADS GenomicsDB variant id
    WHEN UPPER(variant.id) LIKE '%_CHR%' AND variant.id NOT LIKE '%:%' THEN -- structural
        jsonb_agg(jsonb_build_object('variant_primary_key', variant.id))
     END
END AS mapped_variant
FROM variant GROUP BY variant.id
)

SELECT mv.search_term, ((mv.mapped_variant::JSONB)->'annotation')::JSONB AS annotation
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
