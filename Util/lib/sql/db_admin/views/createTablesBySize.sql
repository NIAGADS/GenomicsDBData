CREATE VIEW
    toptablesbysize
    (
        relation,
        total_size
    ) AS
SELECT
    (((n.nspname)::text || '.'::text) || (c.relname)::text)   AS relation,
    pg_size_pretty(pg_total_relation_size((c.oid)::regclass)) AS total_size
FROM
    (pg_class c
LEFT JOIN
    pg_namespace n
ON
    ((
            n.oid = c.relnamespace)))
WHERE
    ((
            n.nspname <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name]))
    AND (
            c.relkind <> 'i'::"char")
    AND (
            n.nspname !~ '^pg_toast'::text))
ORDER BY
    (pg_total_relation_size((c.oid)::regclass)) DESC LIMIT 100;
