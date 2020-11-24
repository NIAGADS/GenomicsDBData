-- builds attributes
CREATE OR REPLACE FUNCTION build_nonlink_badge_attribute(display_value TEXT, download_value TEXT, tooltip TEXT DEFAULT NULL, color TEXT DEFAULT NULL)
        RETURNS JSONB AS $$
DECLARE 
        json JSONB;
BEGIN
	IF display_value IS NULL THEN
	   RETURN NULL;
	END IF;
	SELECT jsonb_build_object('type', 'badge', 'text', display_value, 'value', download_value) INTO json;
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
