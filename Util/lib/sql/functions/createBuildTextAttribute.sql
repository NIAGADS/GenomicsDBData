-- builds attributes
CREATE OR REPLACE FUNCTION build_text_attribute(display_value TEXT,  tooltip TEXT, color TEXT)
        RETURNS JSONB AS $$
DECLARE 
        json JSONB;
BEGIN
	IF display_value IS NULL THEN
	   RETURN NULL;
	END IF;

	SELECT jsonb_build_object('type', 'text', 'value', display_value) INTO json;
	IF tooltip IS NOT NULL THEN
	   SELECT json || jsonb_build_object('tooltip', tooltip) INTO json;
        END IF;
	IF color IS NOT NULL THEN
	   SELECT json || jsonb_build_object('color', color) INTO json;
        END IF;
        RETURN json;
END;
$$

LANGUAGE plpgsql
