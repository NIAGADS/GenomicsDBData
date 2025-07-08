SET work_mem TO '64MB';

INSERT INTO Dataset.DatasetInterval (bin_index, track_id, num_hits, span)
SELECT r.bin_index, 
pan.source_id AS track_id,
count(r.variant_gwas_id) AS num_hits,
int8range(min(position), max(position + length(split_part(r.variant_record_primary_key, ':', 3))-1), '[]') as span
FROM Results.VariantGWAS r, Study.ProtocolAppNode pan
WHERE pan.protocol_app_node_id = r.protocol_app_node_id
GROUP BY r.bin_index, track_id;