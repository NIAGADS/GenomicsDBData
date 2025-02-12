-- finds variant by chr:pos:ref:alt id

DROP FUNCTION find_variant_by_metaseq_id_normalized_variations;
CREATE OR REPLACE FUNCTION find_variant_by_metaseq_id_normalized_variations(metaseqId TEXT, firstHitOnly BOOLEAN DEFAULT FALSE, 
            checkAltAlleles BOOLEAN DEFAULT TRUE)
        RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT, alleles TEXT, variant_class TEXT,
        length INTEGER, is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB, match_rank INTEGER, match_type TEXT) AS $$

DECLARE ref TEXT;
DECLARE alt TEXT;
DECLARE lref INTEGER;
DECLARE lalt INTEGER;

BEGIN

    SELECT split_part(metaseqId, ':', 3)::TEXT INTO ref;
    SELECT split_part(metaseqId, ':', 4)::TEXT INTO alt;
    SELECT LENGTH(ref) INTO lref;
    SELECT LENGTH(alt) INTO lalt;

    IF (((lref > 1 OR lalt > 1) AND (lref < 50 AND lalt < 50))) -- "short" INDEL
        OR (ref = '-' OR alt = '-') -- already normalized
        THEN
        /* normalize alleles and check for exact match */
        RAISE NOTICE 'NORMALIZED (%)', metaseqId;   

        RETURN QUERY
            SELECT *, 3 AS match_rank, 'normalized alleles' AS match_type
            FROM find_variant_by_normalized_metaseq_id(metaseqID, firstHitOnly, checkAltAlleles);

        /*IF NOT FOUND THEN
            IF checkAltAlleles THEN
                RAISE NOTICE 'SWITCH/NORMALIZED (%)', metaseqId;
                RETURN QUERY
                    SELECT *, 4 AS match_rank, 'switch//normalized alleles' AS match_type
                    FROM find_variant_by_normalized_metaseq_id(generate_alt_metaseq_id(metaseqID), firstHitOnly);
            END IF;
        END IF; */
    END IF; 
END;

$$ LANGUAGE plpgsql; 

DROP FUNCTION IF EXISTS find_variant_by_metaseq_id_variations;
CREATE OR REPLACE FUNCTION find_variant_by_metaseq_id_variations(metaseqId TEXT, firstHitOnly BOOLEAN DEFAULT FALSE, 
            checkAltAlleles BOOLEAN DEFAULT TRUE, checkNormalizedAlleles BOOLEAN DEFAULT FALSE)
        RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT, alleles TEXT, variant_class TEXT,
        length INTEGER, is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB, match_rank INTEGER, match_type TEXT) AS $$

BEGIN

    IF array_length(string_to_array(metaseqId, ':'), 1) - 1 = 1 THEN -- chr:pos only
        RAISE NOTICE 'POSITION (%)', metaseqId;
        RETURN QUERY
            SELECT *, 6 AS match_rank, 'position' AS match_type
        FROM find_variant_by_position('chr' || split_part(metaseqId, ':', 1)::text, split_part(metaseqId, ':', 2)::int) r
        ORDER BY LENGTH(r.record_primary_key) ASC
        LIMIT CASE WHEN firstHitOnly THEN 1 END;
    END IF;

    IF metaseqID LIKE '%:N%' THEN -- contains an unknown allele
        IF metaseqID LIKE '%:N:N%' THEN -- containst 2 unknown allele 	 
            RAISE NOTICE 'POSITION (%)', metaseqId;
            RETURN QUERY
	      	 	SELECT *, 6 AS match_rank, 'position' AS match_type
            FROM find_variant_by_position('chr' || split_part(metaseqId, ':', 1)::text, split_part(metaseqId, ':', 2)::int) r
            ORDER BY LENGTH(r.record_primary_key) ASC
            LIMIT CASE WHEN firstHitOnly THEN 1 END;
        ELSE -- contains one unknown allele
            RAISE NOTICE 'POSITION & ALLELE (%)', metaseqId;
            RETURN QUERY
		 	    SELECT *, 5 AS match_rank, 'position and allele' AS match_type
                FROM find_variant_by_position_and_allele('chr' || split_part(metaseqId, ':', 1)::text,
                    split_part(metaseqId, ':', 2)::int,
                    CASE WHEN split_part(metaseqId, ':', 3) = 'N' 
                        THEN split_part(metaseqId, ':', 4) 
                        ELSE split_part(metaseqId, ':', 3) 
                        END) r
                ORDER BY LENGTH(r.record_primary_key) ASC
                LIMIT CASE WHEN firstHitOnly THEN 1 END;
        END IF; -- metaseq 
	END IF; -- metaseq ID contains N

    IF NOT FOUND THEN        
        RAISE NOTICE 'EXACT (%)', metaseqId;
        RETURN QUERY
    	    SELECT *, 1 AS match_rank, 'exact' AS match_type
        FROM find_variant_by_metaseq_id(metaseqId, firstHitOnly);
    END IF;
	
    IF NOT FOUND THEN
        IF checkAltAlleles THEN
            RAISE NOTICE 'SWITCH (%)', metaseqId;
            RETURN QUERY
                SELECT *, 2 AS match_rank, 'switch' AS match_type
                FROM find_variant_by_metaseq_id(generate_alt_metaseq_id(metaseqId), firstHitOnly);

            IF NOT FOUND THEN    
                RAISE NOTICE 'REVERSE COMP (%)', metaseqId;
                RETURN QUERY
                    SELECT *, 5 AS match_rank, 'reverse comp' AS match_type
                    FROM find_variant_by_metaseq_id(generate_rc_metaseq_id(metaseqId), firstHitOnly);
            END IF;

            IF NOT FOUND THEN
                RAISE NOTICE 'RC/SWITCH (%)', metaseqId;
                RETURN QUERY
                    SELECT *, 6 AS match_rank, 'reverse comp//switch' AS match_type
                    FROM find_variant_by_metaseq_id(generate_alt_metaseq_id(generate_rc_metaseq_id(metaseqId)), firstHitOnly);
            END IF;
        END IF;
    END IF;

    IF NOT FOUND THEN
        IF checkNormalizedAlleles THEN
            RETURN QUERY
                SELECT * FROM find_variant_by_metaseq_id_normalized_variations(metaseqId, firstHitOnly, checkAltAlleles);
        END IF;
    END IF; 
END;

$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS find_variant_by_metaseq_id(metaseqId TEXT, firstHitOnly BOOLEAN);
CREATE OR REPLACE FUNCTION find_variant_by_metaseq_id(metaseqId TEXT, firstHitOnly BOOLEAN DEFAULT FALSE)
    RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT, 
                alleles TEXT, variant_class TEXT, length INTEGER,
                is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB) AS $$
    DECLARE chrm TEXT;
BEGIN
    SELECT 'chr' || split_part(metaseqId, ':', 1) INTO chrm;
	RETURN QUERY

	SELECT v.record_primary_key::TEXT, v.ref_snp_id, v.metaseq_id,
    v.display_attributes->>'display_allele' AS alleles,
	v.display_attributes->>'variant_class_abbrev' AS variant_class,
    CASE WHEN v.display_attributes->>'location_start' = v.display_attributes->>'location_end'
        THEN 1
        ELSE (v.display_attributes->>'location_end')::int - (v.display_attributes->>'location_start')::int 
        END AS length,
	CASE WHEN v.is_adsp_variant THEN TRUE ELSE FALSE END AS is_adsp_variant, v.bin_index,
	get_variant_annotation_summary(row_to_json(v)::jsonb) AS annotation
	FROM AnnotatedVDB.Variant v
	WHERE v.metaseq_id = metaseqId
	AND LEFT(v.metaseq_id, 50) = LEFT(metaseqId, 50)
	AND chromosome = chrm
	LIMIT CASE WHEN firstHitOnly THEN 1 END;
END;

$$ LANGUAGE plpgsql;



--firstHitOnly default TRUE b/c positional match
DROP FUNCTION find_variant_by_normalized_metaseq_id(text,boolean, boolean);
CREATE OR REPLACE FUNCTION find_variant_by_normalized_metaseq_id(metaseqId TEXT, firstHitOnly BOOLEAN DEFAULT TRUE,
     checkAltAlleles BOOLEAN DEFAULT FALSE)
    RETURNS TABLE(record_primary_key TEXT, ref_snp_id CHARACTER VARYING, metaseq_id TEXT, 
            alleles TEXT, variant_class TEXT, length INTEGER,
            is_adsp_variant BOOLEAN, bin_index LTREE, annotation JSONB) AS $$

DECLARE chrm TEXT;
DECLARE pos INT;
DECLARE normMetaseqId TEXT;
DECLARE altNormMetaseqId TEXT;

BEGIN
    SELECT 'chr' || split_part(metaseqId, ':', 1) INTO chrm;
    SELECT (split_part(metaseqId, ':', 2))::int INTO pos;
    SELECT CASE WHEN metaseqId LIKE '%-%' 
        THEN metaseqId ELSE generate_normalized_metaseq_id(metaseqId) END 
        INTO normMetaseqId;
    SELECT generate_alt_metaseq_id(normMetaseqId) INTO altNormMetaSeqId;
    
    /* CTE to do positional lookup once */

    RETURN QUERY
        WITH variants AS (SELECT * FROM find_normalized_variant_by_position(chrm, pos)),
        matches AS (
            SELECT v.record_primary_key, 
            v.ref_snp_id, v.metaseq_id, v.alleles, v.variant_class, v.length,
            v.is_adsp_variant, v.bin_index, v.annotation
            FROM variants v 
            WHERE v.normalized_metaseq_id = normMetaseqId)
        SELECT * FROM (SELECT * FROM matches
        UNION ALL
        SELECT v.record_primary_key, 
            v.ref_snp_id, v.metaseq_id, v.alleles, v.variant_class, v.length,
            v.is_adsp_variant, v.bin_index, v.annotation
            FROM variants v 
            WHERE checkAltAlleles 
            AND v.normalized_metaseq_id = altNormMetaseqId
            AND NOT EXISTS (SELECT * FROM matches)) a -- wrapping necesary to order
        ORDER BY LENGTH(a.metaseq_id) ASC
        LIMIT CASE WHEN firstHitOnly THEN 1 END;

        /*SELECT v.record_primary_key, v.ref_snp_id, v.metaseq_id, v.alleles, v.variant_class,
        v.is_adsp_variant, v.bin_index, v.annotation
        FROM find_normalized_variant_by_position(chrm, pos) v
        WHERE v.normalized_metaseq_id = normMetaseqId
        ORDER BY LENGTH(v.metaseq_id) ASC
        LIMIT CASE WHEN firstHitOnly THEN 1 END; */
END;
$$ LANGUAGE plpgsql;

