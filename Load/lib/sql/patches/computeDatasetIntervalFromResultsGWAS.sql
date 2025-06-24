SET work_mem TO '64MB';

INSERT INTO Index.DatasetInterval (bin_index, track_id, num_hits)
SELECT r.bin_index, 
pan.source_id AS track_id,
count(r.variant_gwas_id) AS num_hits
FROM Results.VariantGWAS r, Study.ProtocolAppNode pan
WHERE pan.protocol_app_node_id = r.protocol_app_node_id
GROUP BY r.bin_index, track_id;