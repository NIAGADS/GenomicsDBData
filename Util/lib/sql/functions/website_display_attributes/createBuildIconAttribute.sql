-- builds attributes
CREATE OR REPLACE FUNCTION build_icon_attribute(display_value TEXT, icon TEXT, color TEXT, tooltip TEXT DEFAULT NULL::text, download_value TEXT DEFAULT NULL::text)
        RETURNS JSONB AS $$
DECLARE 
        json JSONB;
BEGIN
	SELECT jsonb_build_object('type', 'icon',  'icon', icon) INTO json;

	IF display_value IS NOT NULL THEN
	   SELECT json || jsonb_build_object('text', display_value) INTO json;
	END IF;

	IF download_value IS NOT NULL THEN
	   SELECT json || jsonb_build_object('value', download_value) INTO json;
	ELSE
	   SELECT json || jsonb_build_object('value', display_value) INTO json;
	END IF;	   

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
