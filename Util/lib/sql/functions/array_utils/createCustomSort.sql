 CREATE OR REPLACE FUNCTION custom_sort(anyarray, anyelement)
  RETURNS INT AS 
'
  SELECT i FROM (
     SELECT generate_series(array_lower($1,1),array_upper($1,1))
  ) g(i)
  WHERE $1[i] = $2
  LIMIT 1;
' LANGUAGE SQL IMMUTABLE;