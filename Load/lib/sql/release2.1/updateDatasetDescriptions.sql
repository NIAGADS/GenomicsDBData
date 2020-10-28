-- patch for dataset collections

UPDATE Study.ProtocolAppNode SET description = description  || '[GWAS Summary Statistics for ADGC African Americans (2013)]' WHERE split_part(source_id, '_', 1) = 'NG00039';
UPDATE Study.ProtocolAppNode SET description = description  || '[Multi-Ethnic Exome Array Study of AD, FTD, and PSP]' WHERE split_part(source_id, '_', 1) = 'NG00040';
UPDATE Study.ProtocolAppNode SET description = description  || '[Genome-wide association summary statistics for ADGC (2011)]' WHERE split_part(source_id, '_', 1) = 'NG00027';
UPDATE Study.ProtocolAppNode SET description = description  || '[IGAP Summary Statistics]' WHERE split_part(source_id, '_', 1) = 'NG00036';
UPDATE Study.ProtocolAppNode SET description = description  || '[GWAS Summary Statistics for Neuropathologic Features of AD and Related Dementias]' WHERE split_part(source_id, '_', 1) = 'NG00041';

