CREATE OR REPLACE FUNCTION truncate_str(str TEXT, numChars INTEGER) 
       RETURNS TEXT AS $$
DECLARE
tstr TEXT;
BEGIN       	       

SELECT CASE WHEN LENGTH(str) > numChars
THEN substr(str, 0, numChars + 1) || '...'
ELSE str END INTO tstr;

RETURN tstr;

END;

$$ LANGUAGE plpgsql;
