-- functions created in public schema so don't have to worry about permissions
-- note: this will return null if location_end == length of chromosome
-- for now, dealing with this by throwing error in loading plugins and if it actually occurs, will revise

-- finds most specific inclusive bin


CREATE OR REPLACE FUNCTION get_chr_size(chr VARCHAR)
       RETURNS INTEGER AS $$
DECLARE 
	chrSize INTEGER;
BEGIN
	SELECT UPPER(location) INTO chrSize
	FROM BinIndexRef
	WHERE chromosome = chr
	AND LEVEL = 0;
	
	RETURN chrSize;
END;
$$
LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION find_bin_index(chr VARCHAR, loc_start INTEGER, loc_end INTEGER) 
        RETURNS LTREE AS $$
DECLARE 
        bin LTREE;
	chrSize INTEGER;
BEGIN
	SELECT  get_chr_size(chr) INTO chrSize;

        SELECT global_bin_path INTO bin 
        FROM BinIndexRef
        WHERE chromosome = chr 
	
	-- case statements handle programmatic flanking regions that may extend past chr boundaries	
        AND location @> int8range(CASE WHEN loc_start < 1 THEN 1 
	    	     		       WHEN loc_start >= chrSize THEN chrSize - 1 
				       ELSE loc_start END, 
	CASE WHEN loc_end >= chrSize THEN chrSize - 1 ELSE loc_end END, '[]')
	
	ORDER BY nlevel(global_bin_path) DESC
	LIMIT 1;	
        
        RETURN bin;
END;
$$
LANGUAGE plpgsql


