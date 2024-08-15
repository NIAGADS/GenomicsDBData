
CREATE OR REPLACE FUNCTION toggleVariantAutovacuum(allow BOOLEAN) RETURNS VOID AS 
$BODY$
DECLARE
        partitionName TEXT;

BEGIN
        FOR partitionName IN 
            SELECT inhrelid::regclass AS child -- optionally cast to text
            FROM   pg_catalog.pg_inherits
            WHERE  inhparent = 'AnnotatedVDB.Variant'::regclass

        LOOP
            IF allow THEN
                EXECUTE 'ALTER TABLE ' || partitionName || ' SET (autovacuum_enabled = on)';
            ELSE
                EXECUTE 'ALTER TABLE ' || partitionName || ' SET (autovacuum_enabled = off)';
            END IF;
            RAISE NOTICE 'EXECUTED: ALTER TABLE % SET (autovacuum_enabled = %)', partitionName, allow;
        END LOOP;

        RETURN;
        
END
$BODY$ 
LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION toggleVariantAutovacuum(BOOLEAN) TO gus_w;