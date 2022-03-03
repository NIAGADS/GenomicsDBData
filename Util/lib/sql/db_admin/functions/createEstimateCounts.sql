CREATE OR REPLACE FUNCTION estimate_row_count(s TEXT, t TEXT) 
       RETURNS TEXT AS $$

DECLARE 
	rCount TEXT;
BEGIN

	SELECT to_char(c.reltuples::bigint, '999G999G990') INTO rCount
	FROM   pg_class c
	JOIN   pg_namespace n ON n.oid = c.relnamespace
	WHERE  n.nspname = LOWER(s)
	AND    c.relname = LOWER(t);
	RETURN rCount;
END;
$$
LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION estimate_result_size(query TEXT) 
RETURNS BIGINT AS $$
DECLARE
   plan JSONB;
BEGIN
   EXECUTE 'EXPLAIN (FORMAT JSON) ' || query INTO plan;
 
   RETURN (plan->0->'Plan'->>'Plan Rows')::BIGINT;
END;
$$
LANGUAGE plpgsql;