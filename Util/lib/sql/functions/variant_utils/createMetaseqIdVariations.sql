
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