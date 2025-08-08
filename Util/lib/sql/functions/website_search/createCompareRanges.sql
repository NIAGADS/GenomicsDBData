CREATE OR REPLACE FUNCTION compare_ranges(
    a int4range,
    b int4range
)
RETURNS TEXT AS $$
BEGIN
    IF a @> b THEN
        RETURN 'contains';
    ELSIF b @> a THEN
        RETURN 'is_contained_within';
    ELSIF upper(a) <= upper(b) AND upper(a) > lower(b) AND a && b THEN
        RETURN 'overlaps';
    ELSIF lower(a) >= lower(b) AND lower(a) < upper(b) AND a && b THEN
        RETURN 'overlaps';
    ELSE
        RETURN 'none';
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

    