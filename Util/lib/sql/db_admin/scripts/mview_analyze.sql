SET WORK_MEM TO '8GB';
SET MAINTENANCE_WORK_MEM TO '8GB';

SELECT 
    string_agg(
       'ANALYZE "' || schemaname || '"."' || relname || '";',
       E'\n' ORDER BY refresh_order) AS script
FROM mat_view_refresh_order WHERE schemaname IN ('cbil', 'niagads')
AND relname not in ('populationkeys') \gset

-- Visualize the script
\echo :script

-- Execute the script
:script
