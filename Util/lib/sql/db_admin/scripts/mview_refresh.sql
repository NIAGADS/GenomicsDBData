-- cannot be run directly; must copy and replace 'myschema' accordingly
-- two scripts: 1) all m-views in a schema
-- 2) all m-views that depend on a particular table

SELECT string_agg(
       'REFRESH MATERIALIZED VIEW "' || schemaname || '"."' || relname || '";',
       E'\n' ORDER BY refresh_order) AS script
FROM mat_view_refresh_order WHERE schemaname='myschema' \gset

-- Visualize the script
\echo :script

-- Execute the script
:script


WITH b AS (
-- Select the highest depth of each mat view name
SELECT DISTINCT ON (schemaname,relname) schemaname, relname, depth
FROM mat_view_dependencies
WHERE relkind='m' AND 
      (start_schemaname,start_relname) IN (('schema1','table1'),('schema2','table2'))
ORDER BY schemaname, relname, depth DESC
)
SELECT string_agg(
       'REFRESH MATERIALIZED VIEW "' || schemaname || '"."' || relname || '";',
       E'\n' ORDER BY depth) AS script
FROM b \gset

-- Visualize the script
\echo :script

-- Execute the script
:script
