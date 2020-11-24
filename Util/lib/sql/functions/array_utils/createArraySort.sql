CREATE OR REPLACE FUNCTION array_sort(anyarray) RETURNS anyarray AS $$
SELECT array_agg(x ORDER BY x) FROM UNNEST($1) x;
$$ LANGUAGE SQL;
