-- from https://stackoverflow.com/a/48889693

CREATE OR REPLACE FUNCTION jsonb_merge(orig jsonb, delta jsonb)
RETURNS JSONB LANGUAGE SQL AS $$
    SELECT
        jsonb_object_agg(
            coalesce(keyOrig, keyDelta),
            CASE
                when valOrig isnull then valDelta
                when valDelta isnull then valOrig
                when (jsonb_typeof(valOrig) <> 'object' or jsonb_typeof(valDelta) <> 'object') then valDelta
                else jsonb_merge(valOrig, valDelta)
            END
        )
    from jsonb_each(orig) e1(keyOrig, valOrig)
    full join jsonb_each(delta) e2(keyDelta, valDelta) on keyOrig = keyDelta
$$;