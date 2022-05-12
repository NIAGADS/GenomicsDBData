
CREATE OR REPLACE FUNCTION variant_msc_gene_impact(conseq JSONB, gene TEXT)
RETURNS text AS $$

SELECT CASE WHEN conseq->>'gene_id' = gene
THEN conseq->>'impact' ELSE NULL END;

$$ LANGUAGE SQL stable;


CREATE OR REPLACE FUNCTION variant_msc_gene_consequence(conseq JSONB, gene TEXT)
RETURNS text AS $$

SELECT CASE WHEN conseq->>'gene_id' = gene
THEN consequence_terms(conseq) ELSE NULL END;

$$ LANGUAGE SQL stable;