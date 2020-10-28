DROP MATERIALIZED VIEW IF EXISTS CBIL.TranscriptAttributes;

CREATE MATERIALIZED VIEW CBIL.TranscriptAttributes AS (
       WITH ecount AS (
       	    SELECT COUNT(e.na_feature_id) AS exon_count,
	    t.na_feature_id AS transcript_id,
	    t.parent_id
	    FROM DoTS.Transcript t, 
	    DoTS.ExonFeature e	 
	    WHERE e.parent_id = t.na_feature_id
	    GROUP BY t.na_feature_id, t.parent_id)
       SELECT g.gene_id,
       g.source_id AS gene_source_id,
       t.source_id AS transcript_source_id,
       l.end_max - l.start_min AS transcript_length,
       ecount.exon_count
       FROM DoTS.GeneFeature gf,
       DoTS.Gene g,
       DoTS.GeneInstance gi,
       DoTS.Transcript t,
       DoTS.NALocation l,
       ecount
       WHERE t.parent_id = gf.na_feature_id
       AND gf.na_feature_id = gi.na_feature_id
       AND gi.gene_id = g.gene_id
       AND l.na_feature_id = t.na_feature_id
       AND ecount.transcript_id = t.na_feature_id
);

CREATE INDEX TA_IND01 ON CBIL.TranscriptAttributes(gene_source_id);
CREATE INDEX TA_IND02 ON CBIL.TranscriptAttributes(transcript_source_id);

GRANT SELECT ON CBIL.TranscriptAttributes TO COMM_WDK_W;
