-- update sequence names and chromosome order in DoTS.ExternalNASequence

UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000001.10', chromosome_order_num = 1 WHERE chromosome = 'chr1';
UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000002.11', chromosome_order_num = 2 WHERE chromosome = 'chr2';
UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000003.11', chromosome_order_num = 3 WHERE chromosome = 'chr3';
UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000004.11', chromosome_order_num = 4 WHERE chromosome = 'chr4';
UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000005.9', chromosome_order_num = 5 WHERE chromosome = 'chr5';

UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000006.11', chromosome_order_num = 6 WHERE chromosome = 'chr6';
UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000007.13', chromosome_order_num = 7 WHERE chromosome = 'chr7';
UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000008.10', chromosome_order_num = 8 WHERE chromosome = 'chr8';
UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000009.11', chromosome_order_num = 9 WHERE chromosome = 'chr9';
UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000010.10', chromosome_order_num = 10 WHERE chromosome = 'chr10';

UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000011.9', chromosome_order_num = 11 WHERE chromosome = 'chr11';
UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000012.11', chromosome_order_num = 12 WHERE chromosome = 'chr12';
UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000013.10', chromosome_order_num = 13 WHERE chromosome = 'chr13';
UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000014.8', chromosome_order_num = 14 WHERE chromosome = 'chr14';
UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000015.9', chromosome_order_num = 15 WHERE chromosome = 'chr15';

UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000016.9', chromosome_order_num = 16 WHERE chromosome = 'chr16';
UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000017.10', chromosome_order_num = 17 WHERE chromosome = 'chr17';
UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000018.9', chromosome_order_num = 18 WHERE chromosome = 'chr18';
UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000019.9', chromosome_order_num = 19 WHERE chromosome = 'chr19';
UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000020.10', chromosome_order_num = 20 WHERE chromosome = 'chr20';

UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000021.8', chromosome_order_num = 21 WHERE chromosome = 'chr21';
UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000022.10', chromosome_order_num = 22 WHERE chromosome = 'chr22';
UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000023.10', chromosome_order_num = 23 WHERE chromosome = 'chrX';
UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_000024.9', chromosome_order_num = 24 WHERE chromosome = 'chrY';
UPDATE DoTS.ExternalNaSequence SET source_id = 'NC_012920.1', chromosome_order_num = 25 WHERE chromosome = 'chrM';
