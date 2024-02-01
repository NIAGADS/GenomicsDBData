-- finds variant by chr:pos:ref:alt id

CREATE OR REPLACE FUNCTION generate_rc_metaseq_id(metaseqID TEXT)
RETURNS TEXT AS $$
DECLARE altId TEXT;
BEGIN
	WITH _array AS (SELECT regexp_split_to_array(metaseqId, ':') AS VALUES)
	SELECT CONCAT(_array.values[1], ':'::text, _array.values[2], ':'::text, reverse_complement(_array.values[3] || ':' || _array.values[4]))
	INTO altId FROM _array;
	RETURN altId;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION generate_alt_metaseq_id(metaseqId TEXT)
            RETURNS TEXT AS $$
DECLARE
	altId TEXT;
BEGIN
	WITH _array AS (SELECT regexp_split_to_array(metaseqId, ':') AS VALUES)
	SELECT CONCAT(_array.values[1], ':'::text, _array.values[2], ':'::text, _array.values[4], ':'::text, _array.values[3]) INTO altId FROM _array;
	RETURN altId;
END;

$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION generate_normalized_metaseq_id(metaseqId TEXT)
            RETURNS TEXT AS $$
DECLARE
	altId TEXT;
BEGIN
    WITH _array AS (SELECT regexp_split_to_array(metaseqId, ':') AS VALUES)
    SELECT  CONCAT(_array.values[1], ':'::text, _array.values[2], ':'::text, 
    CASE WHEN ref = ''  THEN '-' ELSE ref END, ':'::text,
    CASE WHEN alt = ''  THEN '-' ELSE alt END) INTO altID
    FROM _array, normalize_alleles(_array.values[3], _array.values[4]);
    RETURN altId;
END;

$$ LANGUAGE plpgsql; 


--DROP FUNCTION IF EXISTS find_variant_by_metaseq_id_variations(TEXT, BOOLEAN, BOOLEAN);
CREATE OR REPLACE FUNCTION find_variant_by_metaseq_id_variations(metaseqId TEXT, firstHitOnly BOOLEAN DEFAULT FALSE, checkAltAlleles BOOLEAN DEFAULT TRUE)
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT, alleles TEXT, variant_class TEXT,
       	             is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB, match_rank INTEGER, match_type TEXT) AS $$

BEGIN
    IF array_length(string_to_array(metaseqId, ':'), 1) - 1 = 1 THEN -- chr:pos only
        -- RAISE NOTICE 'POSITION';
        RETURN QUERY
            SELECT *, 6 AS match_rank, 'position' AS match_type
        FROM find_variant_by_position('chr' || split_part(metaseqId, ':', 1)::text, split_part(metaseqId, ':', 2)::int, firstHitOnly);
    END IF;

    IF metaseqID LIKE '%:N%' THEN -- contains an unknown allele
        IF metaseqID LIKE '%:N:N%' THEN -- containst 2 unknown allele 	 
            --RAISE NOTICE 'POSITION';
            RETURN QUERY
	      	 	SELECT *, 6 AS match_rank, 'position' AS match_type
		    FROM find_variant_by_position('chr' || split_part(metaseqId, ':', 1)::text, split_part(metaseqId, ':', 2)::int, firstHitOnly);
	    ELSE -- contains one unknown allele
            --RAISE NOTICE 'POSITION & ALLELE';
	      	RETURN QUERY
		 	    SELECT *, 5 AS match_rank, 'position and allele' AS match_type
		 	    FROM find_variant_by_position_and_allele('chr' || split_part(metaseqId, ':', 1)::text,
			        split_part(metaseqId, ':', 2)::int,
			    CASE WHEN split_part(metaseqId, ':', 3) = 'N' 
                    THEN split_part(metaseqId, ':', 4) 
                    ELSE split_part(metaseqId, ':', 3) 
                    END, firstHitOnly);
        END IF; -- metaseq 
	END IF; -- metaseq ID contains N

    IF NOT FOUND THEN        
        --RAISE NOTICE 'EXACT';
	    RETURN QUERY
    	    SELECT *, 1 AS match_rank, 'exact' AS match_type
	        FROM find_variant_by_metaseq_id(metaseqId, firstHitOnly);
    END IF;
	
    IF NOT FOUND THEN
       
	END IF;

    IF checkAltAlleles THEN
        IF NOT FOUND THEN
            --RAISE NOTICE 'SWITCH';
            RETURN QUERY
                SELECT *, 2 AS match_rank, 'switch' AS match_type
                FROM find_variant_by_metaseq_id(generate_alt_metaseq_id(metaseqId), firstHitOnly);
        END IF;

        IF NOT FOUND THEN    
            --RAISE NOTICE 'REVERSE COMP';
            RETURN QUERY
                SELECT *, 4 AS match_rank, 'reverse comp' AS match_type
                FROM find_variant_by_metaseq_id(generate_rc_metaseq_id(metaseqId), firstHitOnly);
        END IF;

        IF NOT FOUND THEN
            --RAISE NOTICE 'RC/SWITCH';
            RETURN QUERY
                SELECT *, 5 AS match_rank, 'reverse comp//switch' AS match_type
                FROM find_variant_by_metaseq_id(generate_alt_metaseq_id(generate_rc_metaseq_id(metaseqId)), firstHitOnly);
        END IF;
    END IF;

    IF NOT FOUND AND (LENGTH(split_part(metaseqID, ':', 3)) > 1 OR LENGTH(split_part(metaseqID, ':', 4)) > 1) THEN
        /* normalize alleles and check for exact match */
        --RAISE NOTICE 'NORMALIZED';
        -- only for INDELS --      
        RETURN QUERY
            SELECT *, 3 AS match_rank, 'normalized alleles' AS match_type
            FROM find_variant_by_normalized_metaseq_id(metaseqID, firstHitOnly);

        IF checkAltAlleles THEN
            IF NOT FOUND THEN
                RAISE NOTICE 'SWITCH/NORMALIZED';
                RETURN QUERY
                    SELECT *, 3 AS match_rank, 'normalized alleles' AS match_type
                    FROM find_variant_by_normalized_metaseq_id(generate_alt_metaseq_id(metaseqID), firstHitOnly);
            END IF;
        END IF;
    END IF;
END;

$$ LANGUAGE plpgsql;

--{"location_end": 122414118, "variant_class": "single nucleotide variant", "display_allele": "G>A", "location_start": 122414118, "sequence_allele": "G/A", "variant_class_abbrev": "SNV"}

DROP FUNCTION IF EXISTS find_variant_by_metaseq_id(metaseqId TEXT, firstHitOnly BOOLEAN);
CREATE OR REPLACE FUNCTION find_variant_by_metaseq_id(metaseqId TEXT, firstHitOnly BOOLEAN DEFAULT FALSE)
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT, alleles TEXT, variant_class TEXT,
       	             is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB) AS $$
BEGIN
	RETURN QUERY
	SELECT v.record_primary_key::TEXT, v.ref_snp_id, v.metaseq_id,
 	v.display_attributes->>'display_allele' AS alleles,
	v.display_attributes->>'variant_class_abbrev' AS variant_class,
	CASE WHEN v.is_adsp_variant THEN TRUE ELSE FALSE END AS is_adsp_variant, v.bin_index,	
	jsonb_build_object(	
	 'associations', v.gwas_flags,
     'allele_frequencies', v.allele_frequencies,
     'cadd_scores', v.cadd_scores,
	 'most_severe_consequence', v.adsp_most_severe_consequence,
	 'ADSP_QC', v.adsp_qc #- '{17k,info,AF}' #- '{17k,info,AC}' #- '{17k,info,AN}',
	 'ranked_consequences', v.adsp_ranked_consequences,
	 'mapped_coordinates', COALESCE(v.other_annotation->'GRCh37' || '{"assembly":"GRCh37"}', v.other_annotation->'GRCh38' || '{"assembly":"GRCh38"}')) AS annotation
	FROM AnnotatedVDB.Variant v
	WHERE v.metaseq_id = metaseqId
	AND LEFT(v.metaseq_id, 50) = LEFT(metaseqId, 50)
	AND chromosome = 'chr' || split_part(metaseqId, ':', 1)::text
	LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;


--firstHitOnly default TRUE b/c positional match
--DROP FUNCTION find_variant_by_normalized_metaseq_id(text,boolean);
CREATE OR REPLACE FUNCTION find_variant_by_normalized_metaseq_id(metaseqId TEXT, firstHitOnly BOOLEAN DEFAULT TRUE)
    RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT, alleles TEXT, variant_class TEXT,
            is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB) AS $$

DECLARE chrm TEXT;
DECLARE pos INT;
DECLARE normMetaseqId TEXT;

BEGIN
    SELECT generate_normalized_metaseq_id(metaseqId) INTO normMetaseqId;
    SELECT 'chr' || split_part(normMetaseqId, ':', 1) INTO chrm;
    SELECT (split_part(normMetaseqId, ':', 2))::int INTO pos;

    RETURN QUERY
        SELECT v.record_primary_key, v.ref_snp_id, v.metaseq_id, v.alleles, v.variant_class,
        v.is_adsp_variant, v.bin_index, v.annotation
        FROM find_variant_by_position(chrm, pos) v
        , generate_normalized_metaseq_id(v.metaseq_id) AS n_metaseq_id
        WHERE n_metaseq_id = normMetaseqId
        LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS find_variant_by_metaseq_id(metaseqId TEXT, chrm TEXT, firstHitOnly BOOLEAN);
CREATE OR REPLACE FUNCTION find_variant_by_metaseq_id(metaseqId TEXT, chrm TEXT, firstHitOnly BOOLEAN DEFAULT FALSE)
        RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT, alleles TEXT, variant_class TEXT,
            is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB) AS $$
BEGIN
	RETURN QUERY
	SELECT v.record_primary_key::TEXT, v.ref_snp_id, v.metaseq_id,
		v.display_attributes->>'display_allele' AS alleles,
		v.display_attributes->>'variant_class_abbrev' AS variant_class,
	        CASE WHEN v.is_adsp_variant THEN TRUE ELSE FALSE END AS is_adsp_variant, v.bin_index,	
	jsonb_build_object(
	 'associations', v.gwas_flags,
     'allele_frequencies', v.allele_frequencies,
     'cadd_scores', v.cadd_scores,
	 'most_severe_consequence', v.adsp_most_severe_consequence,
	 'ranked_consequences', v.adsp_ranked_consequences,
	 'ADSP_QC', v.adsp_qc #- '{17k,info,AF}' #- '{17k,info,AC}' #- '{17k,info,AN}',
	 'mapped_coordinates', COALESCE(v.other_annotation->'GRCh37' || '{"assembly":"GRCh37"}', v.other_annotation->'GRCh38' || '{"assembly":"GRCh38"}')) AS annotation
	FROM AnnotatedVDB.Variant v
	WHERE v.metaseq_id = metaseqId
	AND chromosome = chrm
	LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;

--DROP FUNCTION IF EXISTS get_variant_annotation_by_metaseq_id(text,text,boolean);

CREATE OR REPLACE FUNCTION get_variant_annotation_by_metaseq_id(metaseqId TEXT, chrm TEXT, firstHitOnly BOOLEAN DEFAULT FALSE)
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
       	             has_genomicsdb_annotation BOOLEAN, is_adsp_variant BOOLEAN, bin_index LTREE,
adsp_most_severe_consequence JSONB, cadd_scores JSONB, allele_frequencies JSONB) AS $$

BEGIN
	RETURN QUERY
	SELECT v.record_primary_key::TEXT, v.ref_snp_id, v.metaseq_id, v.has_genomicsdb_annotation, v.is_adsp_variant,
	v.bin_index, v.adsp_most_severe_consequence, v.cadd_scores, v.allele_frequencies 
	FROM AnnotatedVDB.Variant v
	WHERE v.metaseq_id = metaseqId
	AND chromosome = chrm
	LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_variant_annotation_by_metaseq_id(metaseqId TEXT, firstHitOnly BOOLEAN DEFAULT FALSE)
       RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT,
       	             has_genomicsdb_annotation BOOLEAN, is_adsp_variant BOOLEAN, bin_index LTREE,
adsp_most_severe_consequence JSONB, cadd_scores JSONB, allele_frequencies JSONB) AS $$

BEGIN
	RETURN QUERY
	SELECT v.record_primary_key::TEXT, v.ref_snp_id, v.metaseq_id, v.has_genomicsdb_annotation, v.is_adsp_variant,
	v.bin_index, v.adsp_most_severe_consequence, v.cadd_scores, v.allele_frequencies 
	FROM AnnotatedVDB.Variant v
	WHERE v.metaseq_id = metaseqId
	AND chromosome = 'chr' || split_part(metaseqId, ':', 1)::text
	LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;
