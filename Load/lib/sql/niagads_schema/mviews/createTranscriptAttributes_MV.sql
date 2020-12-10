DROP MATERIALIZED VIEW IF EXISTS NIAGADS.TranscriptAttributes;

CREATE MATERIALIZED VIEW NIAGADS.TranscriptAttributes AS (
       SELECT tf.parent_id AS gene_feature_id
       , find_bin_index(nas.source_id, tl.start_min::bigint, tl.end_max::bigint) AS bin_index
       , tf.gene AS gene_source_id
       , tf.na_feature_id AS transcript_feature_id
       , tf.source_id AS transcript_source_id
       , tf.name AS transcript_name
       , tl.start_min::bigint AS location_start
       , tl.end_max::bigint AS location_end
       , tl.is_reversed
       , nas.source_id AS chromosome
       FROM DoTS.Transcript tf,
       DoTS.NALocation tl,
       DoTS.ExternalNASequence nas
       WHERE  tl.na_feature_id = tf.na_feature_id
       AND nas.na_sequence_id = tf.na_sequence_id
);

CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE INDEX TRANSCRIPT_ATTRIBUTES_IND01 ON NIAGADS.TranscriptAttributes(transcript_source_id);
CREATE INDEX TRANSCRIPT_ATTRIBUTES_IND02 ON NIAGADS.TranscriptAttributes(gene_source_id);
CREATE INDEX TRANSCRIPT_ATTRIBUTES_IND03 ON NIAGADS.TranscriptAttributes USING GIST(numrange(location_start, location_end, '[]'));
CREATE INDEX TRANSCRIPT_ATTRIBUTES_IND04 ON NIAGADS.TranscriptAttributes USING GIST(bin_index);

GRANT SELECT ON NIAGADS.TranscriptAttributes TO comm_wdk_w, gus_r, gus_w;
