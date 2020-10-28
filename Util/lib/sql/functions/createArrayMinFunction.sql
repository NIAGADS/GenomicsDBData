CREATE OR REPLACE FUNCTION array_min(anyarray) RETURNS anyelement AS
'SELECT min(i) FROM unnest($1) i' LANGUAGE sql IMMUTABLE;