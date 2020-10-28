DROP MATERIALIZED VIEW IF EXISTS CBIL.GeneLinkOuts;
DROP MATERIALIZED VIEW IF EXISTS CBIL.ClinicalLinkOuts;
DROP MATERIALIZED VIEW IF EXISTS CBIL.NSeqLinkOuts;
DROP MATERIALIZED VIEW IF EXISTS CBIL.ProteinLinkOuts;

CREATE MATERIALIZED VIEW CBIL.GeneLinkOuts AS
(
    WITH Links AS (
    SELECT
        ga.source_id,
        a.external_id,
        string_agg('<a href="' || drl.url || a.external_id || '" class="wdk-toolitp" title="' ||
        drl.resource_full_name || '">' || drl.resource_abbrev || '</a>', ' // ') AS external_links
    FROM
        CBIL.DbRefLink drl,
        CBIL.GeneAttributes ga,
        LATERAL jsonb_each(annotation),
        LATERAL UNNEST(string_to_array(REPLACE(value::text, '"',''), '|')) a(external_id)
    WHERE
        drl.dbref_id = KEY
    AND drl.resource_type = 'gene'
    GROUP BY
        ga.source_id,
        a.external_id
    ORDER BY
        ga.source_id,
        a.external_id )
SELECT
    source_id,
    external_id,
    CASE
        WHEN external_id LIKE 'OTTMUS%'
        THEN REPLACE(external_links, 'Homo_sapiens', 'Mus_musculus')
        ELSE external_links
    END AS external_links
    FROM Links
    ORDER BY source_id, external_id
);

CREATE INDEX GLO_IDX ON CBIL.GeneLinkOuts(source_id);
GRANT SELECT ON CBIL.GeneLinkOuts TO comm_wdk_w;


CREATE MATERIALIZED VIEW CBIL.ClinicalLinkOuts AS
(
  SELECT ga.source_id,
		 a.external_id,
		 string_agg('<a href="' || drl.url || a.external_id || '" class="wdk-toolitp" title="' || drl.resource_full_name || '">' || drl.resource_abbrev || '</a>', ' // ') AS external_links
		 FROM
		 CBIL.DbRefLink drl,
		 CBIL.GeneAttributes ga,
		 LATERAL jsonb_each(annotation),
		 LATERAL UNNEST(string_to_array(replace(value::text, '"',''), '|')) a(external_id)
		 WHERE drl.dbref_id = key
		 AND drl.resource_type = 'clinical'
		 GROUP BY ga.source_id, a.external_id
		 ORDER BY ga.source_id, a.external_id
);

CREATE INDEX CLO_IDX ON CBIL.ClinicalLinkOuts(source_id);
GRANT SELECT ON CBIL.ClinicalLinkOuts TO comm_wdk_w;

CREATE MATERIALIZED VIEW CBIL.NSeqLinkOuts AS 
(
	 SELECT ga.source_id,
		 a.external_id,
		 string_agg('<a href="' || drl.url || a.external_id || '" class="wdk-toolitp" title="' || drl.resource_full_name || '">' || drl.resource_abbrev || '</a>', ' // ') AS external_links
		 FROM
		 CBIL.DbRefLink drl,
		 CBIL.GeneAttributes ga,
		 LATERAL jsonb_each(annotation),
		 LATERAL UNNEST(string_to_array(replace(value::text, '"',''), '|')) a(external_id)
		 WHERE drl.dbref_id = key
		 AND drl.resource_type = 'nucleotide sequences'
		 GROUP BY ga.source_id, a.external_id
		 ORDER BY ga.source_id, a.external_id
);

CREATE INDEX NLO_IDX ON CBIL.NSeqLinkOuts(source_id);
GRANT SELECT ON CBIL.NSeqLinkOuts TO comm_wdk_w;

CREATE MATERIALIZED VIEW CBIL.ProteinLinkOuts AS (
	 SELECT ga.source_id,
		 a.external_id,
		 string_agg('<a href="' || drl.url || a.external_id || '" class="wdk-toolitp" title="' || drl.resource_full_name || '">' || drl.resource_abbrev || '</a>', '  // ') AS external_links
		 FROM
		 CBIL.DbRefLink drl,
		 CBIL.GeneAttributes ga,
		 LATERAL jsonb_each(annotation),
		 LATERAL UNNEST(string_to_array(replace(value::text, '"',''), '|')) a(external_id)
		 WHERE drl.dbref_id = key
		 AND drl.resource_type = 'protein'
		 GROUP BY ga.source_id, a.external_id
		 ORDER BY ga.source_id, a.external_id
);

CREATE INDEX PLO_IDX ON CBIL.ProteinLinkOuts(source_id);
GRANT SELECT ON CBIL.ProteinLinkOuts TO comm_wdk_w;
