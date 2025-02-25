SET WORK_MEM TO '8GB';
SET MAINTENANCE_WORK_MEM TO '8GB';

SELECT 
    string_agg(
       'REFRESH MATERIALIZED VIEW "' || schemaname || '"."' || relname || '";',
       E'\n' ORDER BY refresh_order) AS script
FROM mat_view_refresh_order WHERE schemaname='niagads'
AND relname not in ('advp', 'datadictionaryterms',  'filerbrowsertracks', 'transcriptattributes', 'datasettopfeatures', 'exonattributes', 'gwasbrowsertracks', 'populationkeys', 'variantgwastophits', 'searchablebrowsertrackannotations') \gset

-- Visualize the script
\echo :script

-- Execute the script
:script
