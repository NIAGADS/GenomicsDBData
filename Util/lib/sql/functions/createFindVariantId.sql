-- finds variant id, regardless of annotation status

CREATE OR REPLACE FUNCTION find_variant_id(variantID TEXT)
       RETURNS BIGINT	    AS $$
DECLARE
	internalID TEXT;
BEGIN

WITH 

rvs AS (
SELECT v.variant_id
FROM NIAGADS.Variant v,
(SELECT find_variant_by_refsnp(LOWER(variantID)) AS variant_id  LIMIT 1) mids
WHERE v.variant_id = mids.variant_id
),

mvs AS (
SELECT v.variant_id
FROM NIAGADS.Variant v
WHERE v.metaseq_id = variantID
LIMIT 1
),

MatchedVariants AS (
SELECT * FROM rvs

UNION

SELECT * FROM mvs

UNION 

SELECT v.variant_id
FROM  NIAGADS.Variant v
WHERE v.record_pk = variantID
)

SELECT variant_id INTO internalID FROM MatchedVariants;

RETURN internalID;

END;

$$ LANGUAGE plpgsql;

