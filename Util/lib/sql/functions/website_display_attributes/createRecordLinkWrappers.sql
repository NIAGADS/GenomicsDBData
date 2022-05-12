CREATE OR REPLACE FUNCTION record_link(recordType TEXT, primaryKey TEXT,
       displayId TEXT, isRelative BOOLEAN, tooltip TEXT DEFAULT NULL::TEXT)
RETURNS TEXT AS $$
DECLARE link TEXT;
BEGIN

	IF recordType = 'gene' THEN
	   SELECT gene_record_link(primaryKey, displayId, isRelative, tooltip) INTO link;
	ELSIF recordType = 'variant' THEN
	   SELECT variant_record_link(primaryKey, displayId, isRelative, tooltip) INTO link;
	ELSE -- track
		SELECT track_record_link(primaryKey, displayId, isRelative, tooltip) INTO link;
	END IF;
	RETURN link;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION track_record_link(primaryKey TEXT, displayText TEXT, isRelative BOOLEAN,
       tooltip TEXT DEFAULT NULL::text)
RETURNS TEXT AS $$
DECLARE 
        url TEXT;
	link TEXT;
	helpText TEXT;
BEGIN
	IF isRelative THEN
	   url = '../track/';
	ELSE
	   url = '/record/track/';
	END IF;

	IF tooltip IS NULL THEN
	   helpText = 'Browse track: ' || displayText;
	ELSE
	   helpText = tooltip;
	END IF;
	
	SELECT build_link_attribute(truncate_str(displayText, 50), url, primaryKey, helpText)::text INTO link;
	RETURN link;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION variant_record_link(primaryKey TEXT, metaseqId TEXT, isRelative BOOLEAN,
       tooltip TEXT DEFAULT NULL::text)
RETURNS TEXT AS $$
DECLARE 
        url TEXT;
	link TEXT;
	helpText TEXT;
BEGIN
	IF isRelative THEN
	   url = '../variant/';
	ELSE
	   url = '/record/variant/';
	END IF;

	IF tooltip IS NULL THEN
	   helpText = 'Browse record for variant: ' || metaseqId;
	ELSE
	   helpText = tooltip;
	END IF;
	
	SELECT build_link_attribute(truncate_str(metaseqId, 20), url, primaryKey, helpText)::text INTO link;
	RETURN link;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION gene_record_link(primaryKey TEXT, displayId TEXT, isRelative BOOLEAN,
       tooltip TEXT DEFAULT NULL::TEXT)
RETURNS TEXT AS $$
DECLARE 
        url TEXT;
	link TEXT;
	helpText TEXT;	
BEGIN
	IF isRelative THEN
	   url = '../gene/';
	ELSE
	   url = '/record/gene/';
	END IF;

	IF tooltip IS NULL THEN
	   helpText = 'Browse record for gene: ' || displayId || '//' || primaryKey;
	ELSE
	   helpText = tooltip;
	END IF;
	
	SELECT build_link_attribute(displayId, url, primaryKey, helpText)::text INTO link;
	RETURN link;
END;
$$ LANGUAGE plpgsql;




