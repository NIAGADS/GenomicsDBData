-- like jsonb_build_array but removes null elements
-- https://stackoverflow.com/questions/51432543/postgresql-json-building-an-array-without-null-values
CREATE OR REPLACE FUNCTION jsonb_build_array_check_nulls(variadic ANYARRAY)
        RETURNS JSONB AS $$
DECLARE 
        json JSONB;
BEGIN
	SELECT jsonb_agg(elem) INTO json
	FROM UNNEST($1) AS elem
	WHERE elem IS NOT NULL;
	RETURN json;
END;
$$

LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION jsonb_strip_nulls(input jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$

        SELECT jsonb_object_agg(key, value) AS obj
        FROM jsonb_each(input)
        WHERE value IS NOT NULL
    
$$;