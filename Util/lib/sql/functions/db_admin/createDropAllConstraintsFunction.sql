
CREATE OR REPLACE FUNCTION dropAllConstraints(text, text, boolean) RETURNS SETOF text AS 
$BODY$
DECLARE
        schema_name ALIAS FOR $1; 
        table_name ALIAS FOR $2;
        listOnly ALIAS FOR $3;
        constraintList text[];
        constraint_name text;
BEGIN
        FOR constraint_name IN 
        SELECT conname 
        FROM pg_constraint pc
         INNER JOIN pg_class ON conrelid=pg_class.oid 
         INNER JOIN pg_namespace ON pg_namespace.oid=pg_class.relnamespace 
        AND contype = 'f' AND nspname = LOWER(schema_name) AND relname = LOWER(table_name)
  
        
        LOOP
                IF constraint_name NOT LIKE '%pk%' THEN
                        IF NOT listOnly THEN
                                EXECUTE 'ALTER TABLE ' || schema_name || '.' || table_name || ' DROP constraint ' || constraint_name;
                        END IF;
                        constraintList := array_append(constraintList, constraint_name);
                END IF;
        END LOOP;
        
        FOR i IN 1..array_upper(constraintList, 1) LOOP
                RETURN NEXT constraintList[i];
        END LOOP;
        RETURN;
        
END
$BODY$ 
LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION dropAllConstraints(TEXT, TEXT, BOOLEAN) TO gus_w;
