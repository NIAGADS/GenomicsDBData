-- builds attributes
CREATE OR REPLACE FUNCTION build_link_attribute(display_value TEXT, url TEXT, url_parameter TEXT DEFAULT NULL, tooltip TEXT DEFAULT NULL)
        RETURNS JSONB AS $$
DECLARE 
        json JSONB;
BEGIN
	IF display_value IS NULL THEN
	   RETURN NULL;
	END IF;
	IF url_parameter IS NULL THEN
	    url := url || display_value;
        ELSE
	    url := url || url_parameter;
	END IF;
	SELECT jsonb_build_object('type', 'link', 'url', url, 'value', display_value) INTO json;
	IF tooltip IS NOT NULL THEN
	   SELECT json || jsonb_build_object('tooltip', tooltip) INTO json;
        END IF;
        RETURN json;
END;
$$

LANGUAGE plpgsql
