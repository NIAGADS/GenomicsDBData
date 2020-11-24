CREATE OR REPLACE FUNCTION dropAllIndexes(text, text) RETURNS SETOF text AS 
$BODY$
DECLARE
        schema_name ALIAS FOR $1; 
        table_name ALIAS FOR $2;
        indexList text[];
        index_name text;
BEGIN
        FOR index_name IN 
        SELECT t.schemaname || '.' || ci.relname AS index_name
        FROM pg_tables t, pg_index i, pg_class ci, pg_class ct
        WHERE t.schemaname = LOWER(schema_name)
        AND t.tablename = LOWER(table_name)
        AND t.tablename = ct.relname
        AND ct.oid = i.indrelid
        AND i.indexrelid = ci.oid
        
        LOOP
                IF index_name NOT LIKE '%pk%' THEN
                        EXECUTE 'DROP INDEX ' || index_name;
                        indexList := array_append(indexList, index_name);
                END IF;
        END LOOP;
        
        FOR i IN 1..array_upper(indexList, 1) LOOP
                RETURN NEXT indexList[i];
        END LOOP;
        RETURN;
        
END
$BODY$ 
LANGUAGE plpgsql;


GRANT EXECUTE ON FUNCTION dropAllIndexes(TEXT, TEXT) TO gus_w;	
