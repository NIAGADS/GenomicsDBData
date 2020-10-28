-- builds an item for a dictionary attribute to be displayed as key-value pairs
CREATE OR REPLACE FUNCTION build_dictionary_element(label TEXT, display_value JSONB)
        RETURNS JSONB AS $$
DECLARE 
        json JSONB;
BEGIN
	IF DISPLAY_VALUE IS NULL THEN
	   RETURN NULL;
	END IF;
	SELECT jsonb_build_object('key', label, 'value', display_value) INTO json;
        RETURN json;
END;
$$

LANGUAGE plpgsql
