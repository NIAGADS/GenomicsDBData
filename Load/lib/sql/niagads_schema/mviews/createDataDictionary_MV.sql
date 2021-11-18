DROP MATERIALIZED VIEW IF EXISTS NIAGADS.DataDictionary;

CREATE MATERIALIZED VIEW NIAGADS.DataDictionary AS (
SELECT ot.source_id AS term_source_id,
ot.name,
ot.uri,
ot.definition,
nc.category_level_1,
nc.category_level_2,
nc.category_level_3,
nc.category_level_4,
ot.ontology_term_id
FROM SRes.OntologyTerm ot, NIAGADS.NDDCategories nc
WHERE ot.notes = 'NDD'
AND ot.source_id = nc.term_source_id
ORDER BY ot.source_id
);

CREATE INDEX NIAGADS_DD_INDX01 ON NIAGADS.DataDictionary(term_source_id);
CREATE INDEX NIAGADS_DD_INDX02 ON NIAGADS.DataDictionary(category_level_1);
CREATE INDEX NIAGADS_DD_INDX03 ON NIAGADS.DataDictionary(category_level_2);
CREATE INDEX NIAGADS_DD_INDX04 ON NIAGADS.DataDictionary(category_level_3);
CREATE INDEX NIAGADS_DD_INDX05 ON NIAGADS.DataDictionary(category_level_4);

GRANT SELECT ON NIAGADS.DataDictionary TO gus_r, gus_w, comm_wdk_w;
