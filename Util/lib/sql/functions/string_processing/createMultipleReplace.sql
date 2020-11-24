
CREATE OR REPLACE FUNCTION multi_replace(str TEXT, oldText TEXT[], newText TEXT[])
       RETURNS TEXT AS $$
DECLARE
	i INTEGER;	
BEGIN
   FOR i IN 1.. array_length(oldText, 1)
   LOOP
       SELECT replace(str, oldText[i], newText[i]) INTO str;
   END LOOP;
   RETURN str;	
END;
$$ LANGUAGE plpgsql
