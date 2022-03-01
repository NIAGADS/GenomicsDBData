CREATE VIEW
    toprelationsbysize
    (
        relation,
        SIZE
    ) AS
SELECT
    (((n.nspname)::text || '.'::text) || (c.relname)::text) AS relation,
    pg_size_pretty(pg_relation_size((c.oid)::regclass))     AS SIZE
FROM
    (pg_class c
LEFT JOIN
    pg_namespace n
ON
    ((
            n.oid = c.relnamespace)))
WHERE
    (
        n.nspname <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name]))
ORDER BY
    (pg_relation_size((c.oid)::regclass)) DESC LIMIT 100;
