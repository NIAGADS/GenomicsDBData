CREATE FUNCTION isnumeric(text) RETURNS boolean AS '
SELECT $1 ~ ''^[0-9]+$''
' LANGUAGE 'sql';
