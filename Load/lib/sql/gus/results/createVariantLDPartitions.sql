-- function creates partitions for the Results.VariantLD table based on
-- chromosomes in dots.externalnasequence

CREATE OR REPLACE FUNCTION create_variantld_partition() RETURNS INTEGER AS
  $BODY$
    DECLARE
      partition TEXT;
      chr TEXT;
    BEGIN

      FOR chr IN
        SELECT source_id FROM DoTS.ExternalNASequence WHERE source_id LIKE 'chr%'
      LOOP
        partition := 'Results.VariantLD' || '_' || chr::text;
        IF NOT EXISTS(SELECT relname FROM pg_class WHERE relname=partition) THEN
           EXECUTE 'CREATE TABLE ' || partition || ' PARTITION OF Results.VariantLD FOR VALUES IN (''' || chr || ''')';
           RAISE NOTICE 'A partition has been created %',partition;
         END IF;
      END LOOP;
      RETURN NULL;
    END;

  $BODY$
LANGUAGE plpgsql VOLATILE;
