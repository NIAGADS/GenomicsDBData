-- function creates an indexed array map of values in a column
-- for specifying custom sort orders, e.g.,
-- SELECT * FROM Results.SeqVariation ORDER BY idx(array['HIGH', 'MODERATE', 'LOW', 'MODIFIER'], label)

CREATE OR REPLACE FUNCTION idx(text[], anyelement)
  RETURNS INT AS 
$$
  SELECT i FROM (
     SELECT generate_series(array_lower($1,1),array_upper($1,1))
  ) g(i)
  WHERE $1[i] = $2
  LIMIT 1;
$$ LANGUAGE SQL IMMUTABLE;
