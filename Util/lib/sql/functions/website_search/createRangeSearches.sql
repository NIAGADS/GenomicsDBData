
DROP FUNCTION genes_by_range_lookup(text,int,int);
CREATE OR REPLACE FUNCTION genes_by_range_lookup(chrm TEXT, locStart INT, locEnd INT)
    RETURNS TABLE(gene JSONB, gene_type TEXT, location JSONB, range_relation TEXT) AS $$

DECLARE 
    binIndex LTREE;
BEGIN
    SELECT find_bin_index(chrm, locStart, locEnd) INTO binIndex;

    RETURN QUERY
        SELECT jsonb_build_object('id', source_id, 'gene_symbol', gene_symbol) as gene, ga.gene_type,
        jsonb_build_object('chromosome', chrm, 'start', ga.location_start, 'end', ga.location_end) AS location,
        compare_ranges(int4range(locStart, locEnd, '[]'), int4range(ga.location_start, ga.location_end)) AS range_relation 
        FROM CBIL.GeneAttributes ga
        WHERE chromosome = chrm
        AND (
            -- in same bin and overlaps
            (binIndex @> ga.bin_index 
            AND int4range(locStart, locEnd, '[]') && int4range(ga.location_start, ga.location_end))
            
            OR
            -- range is a containing bin that overlaps
            (binIndex <@ ga.bin_index 
            AND int4range(locStart, locEnd, '[]') && int4range(ga.location_start, ga.location_end))  

           /* OR 
            (binIndex = ga.bin_index 
             AND  locStart = ga.location_start and locEnd = ga.location_end)*/
        );
END;

$$ LANGUAGE plpgsql;


DROP FUNCTION summarize_genes_by_range(text,int,int);
CREATE OR REPLACE FUNCTION summarize_genes_by_range(chrm TEXT, locStart INT, locEnd INT)
    RETURNS TABLE(num_genes INT, range_relation TEXT, gene_type TEXT) AS $$

DECLARE 
    binIndex LTREE;
BEGIN
    SELECT find_bin_index(chrm, locStart, locEnd) INTO binIndex;

    RETURN QUERY
        WITH g AS (
            SELECT source_id as gene_id, 
            ga.gene_type,
            compare_ranges(int4range(locStart, locEnd, '[]'), int4range(ga.location_start, ga.location_end)) AS range_relation 
            FROM CBIL.GeneAttributes ga
            WHERE chromosome = chrm
            AND (
                -- in same bin and overlaps
                (binIndex @> ga.bin_index 
                AND int4range(locStart, locEnd, '[]') && int4range(ga.location_start, ga.location_end))
                
                OR
                -- range is a containing bin that overlaps
                (binIndex <@ ga.bin_index 
                AND int4range(locStart, locEnd, '[]') && int4range(ga.location_start, ga.location_end))  
            )
        )
    
            SELECT COUNT (gene_id)::int AS num_genes, g.range_relation, g.gene_type 
            FROM g GROUP BY g.gene_type, g.range_relation ORDER BY num_genes DESC
  ;
END;

$$ LANGUAGE plpgsql;



DROP FUNCTION variants_by_range_lookup(text,int,int);
CREATE OR REPLACE FUNCTION variants_by_range_lookup(chrm TEXT, locStart INT, locEnd INT)
    RETURNS TABLE(variant JSONB, variant_type TEXT, location JSONB, range_relation TEXT) AS $$

DECLARE 

BEGIN
    RETURN QUERY
        WITH v AS (
        SELECT annotation->'annotation' AS variant -- FIXME
        FROM find_variants_by_range(chrm, locStart,locEnd))
        SELECT v.variant, CASE WHEN (v.variant->'annotation'->>'is_structural_variant')::boolean IS TRUE THEN 'structural variant' ELSE 'small variant' END AS variant_type,
        v.variant->'location' AS location, 
        compare_ranges(int4range(locStart, locEnd, '[]') ,
        int4range((v.variant->'location'->>'start')::int, 
        CASE WHEN (v.variant->'location'->>'length')::int = 1 THEN (v.variant->'location'->>'start')::int
        ELSE (v.variant->'location'->>'start')::int + (v.variant->'location'->>'length')::int END)) AS range_relation
        FROM v;
END;

$$ LANGUAGE plpgsql;


DROP FUNCTION summarize_variants_by_range(text,int,int, boolean);
CREATE OR REPLACE FUNCTION summarize_variants_by_range(chrm TEXT, locStart INT, locEnd INT, svsOnly BOOLEAN DEfAULT FALSE)
     RETURNS TABLE(num_variants INT, range_relation TEXT, variant_type TEXT) AS $$

DECLARE 
    binIndex LTREE;
BEGIN
    SELECT find_bin_index(chrm, locStart, locEnd) INTO binIndex;

    RETURN QUERY 
       WITH RESULT AS (SELECT 
      v.metaseq_id AS variant_id, 
      jsonb_build_object(
            'chromosome', v.chromosome,
            'start', (v.display_attributes->>'location_start')::INT,
            'length', CASE WHEN (v.is_structural_variant)::boolean IS TRUE THEN (v.display_attributes->>'sv_size')::INT
            ELSE length(split_part(v.metaseq_id, ':', 3)) --length REF
            END
        ) AS location,
        v.is_structural_variant,
        v.display_attributes->>'variant_class_abbrev' AS variant_type
    FROM AnnotatedVDB.Variant v
     WHERE v.chromosome = chrm
     AND ((svsOnly AND v.is_structural_variant IS TRUE) OR NOT svsOnly)
     AND (
      -- contained, location_start = location_end
      (v.display_attributes->>'location_start' = v.display_attributes->>'location_end'
      AND binIndex @> v.bin_index 
      AND int4range(locStart, locEnd, '[]') @> int4range(v.position, v.position + 1))
     
      OR 
      
      -- in same bin and overlaps
      (binIndex @> v.bin_index 
      AND int4range(locStart, locEnd, '[]') && int4range((v.display_attributes->>'location_start')::int, (v.display_attributes->>'location_end')::int ))
      
      OR
      -- sv in containing bin and overlaps
      (v.bin_index @> binIndex
      AND int4range(locStart, locEnd, '[]') && int4range((v.display_attributes->>'location_start')::int, (v.display_attributes->>'location_end')::int ))
     )),
     
     RangeTypes AS (
     SELECT r.variant_id, r.location, 
    CASE WHEN r.is_structural_variant IS TRUE THEN 'SV_' || r.variant_type ELSE r.variant_type END AS variant_type, 
    compare_ranges(int4range(locStart, locEnd, '[]') ,
        int4range((r.location->>'start')::int, 
        CASE WHEN (r.location->>'length')::int = 1 THEN (r.location->>'start')::int
        ELSE (r.location->>'start')::int + (r.location->>'length')::int END)) AS range_relation
    FROM Result r)
    SELECT COUNT (variant_id)::int AS num_variants, r.range_relation, r.variant_type 
    FROM RangeTypes r GROUP BY r.variant_type, r.range_relation ORDER BY num_variants DESC
    ;
 

END;
$$ LANGUAGE plpgsql;


DROP FUNCTION find_svs_by_range(text,int,int);
CREATE OR REPLACE FUNCTION find_svs_by_range(chrm TEXT, locStart INT, locEnd INT)
    RETURNS TABLE(variant_id TEXT, annotation JSONB) AS $$

DECLARE 
    binIndex LTREE;
BEGIN
    SELECT find_bin_index(chrm, locStart, locEnd) INTO binIndex;

    RETURN QUERY
    SELECT t.variant_id, row_to_json(t)::jsonb FROM (
    SELECT v.metaseq_id AS variant_id, v.ref_snp_id,
    v.display_attributes->>'display_allele' AS alleles,
	v.display_attributes->>'variant_class_abbrev' AS variant_class,
    v.chromosome,
    v.position,
    -- (v.display_attributes->>'location_end')::int - (v.display_attributes->>'location_start')::int AS length,
	CASE WHEN v.is_adsp_variant THEN TRUE ELSE FALSE END AS is_adsp_variant, v.bin_index,
	get_variant_annotation_summary(row_to_json(v)::jsonb) AS annotation
    
    FROM AnnotatedVDB.Variant v
    WHERE v.chromosome = chrm
    AND v.is_structural_variant IS TRUE
     AND (        
      -- in same bin and overlaps
      (binIndex @> v.bin_index
      AND int4range(locStart, locEnd, '[]') && int4range((v.display_attributes->>'location_start')::int, (v.display_attributes->>'location_end')::int ))
      
      OR
      -- sv in containing bin and overlaps
      (v.bin_index @> binIndex
      AND int4range(locStart, locEnd, '[]') && int4range((v.display_attributes->>'location_start')::int, (v.display_attributes->>'location_end')::int ))
     )
    ) t;

END;

$$ LANGUAGE plpgsql;

DROP FUNCTION sv_by_range_lookup(text,int,int);
CREATE OR REPLACE FUNCTION sv_by_range_lookup(chrm TEXT, locStart INT, locEnd INT)
    RETURNS TABLE(variant JSONB, variant_type TEXT, location JSONB,range_relation TEXT) AS $$

DECLARE 

BEGIN
    RETURN QUERY
        WITH v AS (
        SELECT annotation->'annotation' AS variant -- FIXME
        FROM find_svs_by_range(chrm, locStart,locEnd))
        SELECT v.variant, 'structural variant' AS variant_type, v.variant->'location' AS location, 
        compare_ranges(int4range(locStart, locEnd, '[]') ,
        int4range((v.variant->'location'->>'start')::int, 
        CASE WHEN (v.variant->'location'->>'length')::int = 1 THEN (v.variant->'location'->>'start')::int
        ELSE (v.variant->'location'->>'start')::int + (v.variant->'location'->>'length')::int END)) AS range_relation
        FROM v;
END;

$$ LANGUAGE plpgsql;