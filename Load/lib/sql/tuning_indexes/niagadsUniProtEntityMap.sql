CREATE INDEX UPEM_DATABASE ON NIAGADS.UniProtEntityMap (database);
CREATE INDEX UPEM_UNIPROT ON NIAGADS.UniProtEntityMap (uniprot_id);
CREATE INDEX UPEM_ENSEMBL_GENE ON NIAGADS.UniProtEntityMap (mapped_id, uniprot_id) WHERE database = 'Ensembl';
CREATE INDEX UPEM_ID_BY_DB ON NIAGADS.UniProtEntityMap (database, mapped_id);
CREATE INDEX UPEM_ID ON NIAGADS.UniProtEntityMap (mapped_id);
