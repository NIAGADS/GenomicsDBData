-- with the assistance of ChatGPT
CREATE OR REPLACE FUNCTION transform_case_control_json(input_json jsonb)
RETURNS jsonb LANGUAGE sql AS
$$
WITH types AS (
    SELECT
        jsonb_typeof(input_json->'ncase') AS ncase_type,
        jsonb_typeof(input_json->'ncontrol') AS ncontrol_type,
        input_json->'ncase' AS ncase_raw,
        input_json->'ncontrol' AS ncontrol_raw
),
-- Case: both are scalars or one exists as scalar and the other is missing
scalar_case AS (
    SELECT jsonb_agg(
        jsonb_build_object(
            'num_cases', COALESCE((ncase_raw)::int, NULL),
            'num_controls', COALESCE((ncontrol_raw)::int, NULL)
        )
    ) AS result
    FROM types
    WHERE (ncase_type IS NULL OR ncase_type != 'object')
      AND (ncontrol_type IS NULL OR ncontrol_type != 'object')
),
-- Case: one or both are objects
object_case AS (
    WITH safe_json AS (
        SELECT
            CASE WHEN ncase_type = 'object' THEN ncase_raw ELSE '{}'::jsonb END AS ncase_obj,
            CASE WHEN ncontrol_type = 'object' THEN ncontrol_raw ELSE '{}'::jsonb END AS ncontrol_obj
        FROM types
    ),
    terms AS (
        SELECT jsonb_object_keys(ncase_obj) AS term FROM safe_json
        UNION
        SELECT jsonb_object_keys(ncontrol_obj) AS term FROM safe_json
    )
    SELECT jsonb_agg(
        jsonb_build_object(
            'phenotype', jsonb_build_object('term', term),
            'num_cases', COALESCE((ncase_obj->>term)::int, NULL),
            'num_controls', COALESCE((ncontrol_obj->>term)::int, NULL)
        )
    ) AS result
    FROM terms, safe_json
)
-- Return scalar version if present, else object version, else empty array
SELECT COALESCE(scalar_case.result, object_case.result, '[]'::jsonb)
FROM scalar_case, object_case;
$$;