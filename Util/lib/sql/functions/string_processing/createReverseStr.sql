CREATE OR REPLACE FUNCTION reverse_str(text) RETURNS text AS $$
SELECT array_to_string(ARRAY(
  SELECT SUBSTRING($1, s.i,1) FROM generate_series(LENGTH($1), 1, -1) AS s(i)
  ), '');
$$ LANGUAGE SQL IMMUTABLE STRICT;
