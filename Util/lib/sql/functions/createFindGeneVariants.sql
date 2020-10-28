-- functions created in public schema so don't have to worry about permissions
-- note: this will return null if location_end == length of chromosome
-- for now, dealing with this by throwing error in loading plugins and if it actually occurs, will revise

CREATE OR REPLACE FUNCTION find_bin_index(chr VARCHAR, loc_start NUMERIC, loc_end NUMERIC) 
        RETURNS LTREE AS $$
DECLARE 
        bin TEXT;
BEGIN
        SELECT global_bin_path INTO bin 
        FROM CBIL.BinIndexRef 
        WHERE chromosome = chr 
        AND numrange(location_start, location_end, '[)') @> numrange(loc_start, loc_end, '[]')
	ORDER BY nlevel(global_bin_path) DESC
	LIMIT 1;	
        
        RETURN bin;
END;
$$
LANGUAGE plpgsql
