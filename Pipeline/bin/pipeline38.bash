# =================================================
# REFERENCE BUILD - Load Genome
# =================================================

# Sequence Ontology

loadResource --config $CONFIG_DIR/ontologies/sequence_ontology.json --load xdbr --commit > $DATA_DIR/logs/xdbr/load_sequence_ontology_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/sequence_ontology.json --load data --commit > $DATA_DIR/logs/ontologies/load_sequence_ontology.log 2>&1

# Taxon

ga GUS::Supported::Plugin::LoadGusXml --filename $GUS_HOME/lib/xml/sres/taxon.xml --comment "ga GUS::Supported::Plugin::LoadGusXml --filename $GUS_HOME/lib/xml/sres/taxon.xml" --commit > $DATA_DIR/logs/load_taxon.log 2>&1

# Genome

loadResource --config $CONFIG_DIR/reference_databases/hg38_genome.json --load xdbr --commit > $DATA_DIR/logs/xdbr/load_hg38_genome_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/hg38_genome.json --load data --commit > $DATA_DIR/logs/reference/load_hg38_genome.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/hg38_genome.json --tuning --verbose --commit > $DATA_DIR/logs/reference/patch_hg38_genome.log 2>&1


# =================================================
# Patch DB & Create Additional Schemas / requires BinIndex, which depends on the chromosome map
# =================================================

# CREATE BinIndex Reference & Related Triggers/Lookusp
generateChrMapFile --outputFile /home/allenem/hg38/project_home/GenomicsDBData/Load/data/chr_map_gencode36_grch38_p13.txt

psql_rls --file $PROJECT_HOME/GenomicsDBData/BinIndex/lib/sql/createBinIndexRef.sql -a > $DATA_DIR/logs/create_bin_index_table.log 2>&1

generate_bin_index_references.py -m $PROJECT_HOME/GenomicsDBData/Load/data/chr_map_gencode36_grch38_p13.txt --commit > $DATA_DIR/logs/generate_bin_index.log 2>&1

psql_rls --file $PROJECT_HOME/GenomicsDBData/Load/lib/sql/triggers/createSetRowBinIndexTrigger.sql -a > $DATA_DIR/logs/create_set_row_bin_index_trigger.sql 2>&1

psql_rls --file $PROJECT_HOME/GenomicsDBData/BinIndex/lib/sql/createFindBinIndex -a > $DATA_DIR/logs/create_find_bin_index_function.sql 2>&1

# Patch GUS / Install CBIL Schema / Create Utility Functions

installCBILSchema --verbose --patchGUS > $DATA_DIR/logs/install_cbil_schema_patch_gus.log 2>&1
installCBILSchema --verbose --createFunctions > $DATA_DIR/logs/install_cbil_schema_create_functions.log 2>&1
installCBILSchema --verbose --createSchema > $DATA_DIR/logs/install_cbil_schema_create_schema.log 2>&1
installCBILSchema --verbose --createTables > $DATA_DIR/logs/install_cbil_schema_create_tables.log 2>&1

# Install NIAGADS Schema

installNiagadsSchema --verbose --createSchema > $DATA_DIR/logs/install_niagads_schema_create_schema.log 2>&1
installNiagadsSchema --verbose --createTables > $DATA_DIR/logs/install_niagads_schema_create_tables.log 2>&1

# Install AnnotatedVDB Schema

installAnnotatedVDBSchema --verbose --createSchema > $DATA_DIR/logs/install_annotatedvdb_schema_create_schema.sql 2>&1
installAnnotatedVDBSchema --verbose --createTables > $DATA_DIR/logs/install_annotatedvdb_schema_create_tables.sql 2>&1


# =================================================
# REFERENCE BUILD - Genes / Gene Annotation
# =================================================

loadResource --config $CONFIG_DIR/reference_databases/hg38_genes.json --load xdbr --commit > $DATA_DIR/logs/xdbr/load_hg38_genes_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/hg38_genes.json --preprocess --verbose > $DATA_DIR/logs/reference/load_hg38_genes_preprocess.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/hg38_genes.json --load data --commit  > $DATA_DIR/logs/reference/load_hg38_genes.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/hg38_genes.json --tuning --verbose --commit  > $DATA_DIR/logs/tuning/create_transcript_mv.log 2>&1

# HGNC

loadResource --config $CONFIG_DIR/reference_databases/hgnc.json --load xdbr --commit > $DATA_DIR/logs/xdbr/load_hgnc_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/hgnc.json --preprocess --verbose > $DATA_DIR/logs/reference/preprocess_hgnc.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/hgnc.json --load data --verbose --commit  > $DATA_DIR/logs/reference/load_hgnc.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/hgnc.json --tuning --verbose --commit  > $DATA_DIR/logs/tuning/index_and_create_gene_attributes.log 2>&1

# GO

loadResource --config $CONFIG_DIR/ontologies/gene_ontology.json --load xdbr --commit --verbose > $DATA_DIR/logs/xdbr/load_gene_ontology_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/gene_ontology.json --preprocess --verbose > $DATA_DIR/logs/ontologies/preprocess_gene_ontology.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/gene_ontology.json --load data --commit --verbose > $DATA_DIR/logs/ontologies/load_gene_ontology.log 2>&1

# Niagads Ontology (needed for subClassOf relationship)

loadResource --config $CONFIG_DIR/ontologies/niagads_ontology.json --load xdbr --commit --verbose > $DATA_DIR/logs/xdbr/load_niagads_ontology_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/niagads_ontology.json --preprocess --verbose > $DATA_DIR/logs/ontologies/preprocess_niagads_ontology.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/niagads_ontology.json --load data --commit --verbose > $DATA_DIR/logs/ontologies/load_niagads_ontology.log 2>&1

# EDAM Ontology (needed for Go reference bib ref type)

loadResource --config $CONFIG_DIR/ontologies/edam.json --load xdbr --commit --verbose > $DATA_DIR/logs/xdbr/load_edam_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/edam.json --load data --commit --verbose > $DATA_DIR/logs/ontologies/load_edam.log 2>&1

# GO Reference
loadResource --config $CONFIG_DIR/reference_databases/go_references.json --load xdbr --commit --verbose > $DATA_DIR/logs/xdbr/load_go_references_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/go_references.json --preprocess --verbose > $DATA_DIR/logs/reference/preprocess_go_references.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/go_references.json --load data --commit --verbose > $DATA_DIR/logs/reference/load_go_references.log 2>&1

# ECO - Evidence Ontology (needed for Gene-GO Association Plugin)

loadResource --config $CONFIG_DIR/ontologies/eco.json --load xdbr --commit --verbose > $DATA_DIR/logs/xdbr/load_eco_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/eco.json --load data --commit --verbose > $DATA_DIR/logs/ontologies/load_eco.log 2>&1


# UniProt ID Mappings -- no good / less accurate than HGNC

# loadResource --config $CONFIG_DIR/reference_databases/uniprot_entity_map.json --load xdbr --commit --verbose > $DATA_DIR/logs/xdbr/load_uniprot_entity_map_xdbr.log 2>&1
# loadResource --config $CONFIG_DIR/reference_databases/uniprot_entity_map.json --load data --commit --verbose > $DATA_DIR/logs/reference/load_uniprot_entity_map.log 2>&1
# loadResource --config $CONFIG_DIR/reference_databases/uniprot_entity_map.json --tuning --commit --verbose > $DATA_DIR/logs/tuning/load_uniprot_entity_map_tuning_indexes.log 2>&1

# Gene-GO Association

loadResource --config $CONFIG_DIR/reference_databases/go_gene_annotation.json --load xdbr --commit --verbose > $DATA_DIR/logs/xdbr/load_go_gene_association_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/go_gene_annotation.json --preprocess --verbose > $DATA_DIR/logs/reference/preprocess_go_gene_annotation.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/go_gene_annotation.json --load data --commit --verbose > $DATA_DIR/logs/reference/load_go_gene_association.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/go_gene_annotation.json --tuning --verbose > $DATA_DIR/logs/tuning/load_go_gene_association_tuning.log 2>&1

# KEGG
loadResource --config $CONFIG_DIR/reference_databases/kegg.json --load xdbr --verbose --commit > $DATA_DIR/logs/xdbr/load_kegg_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/kegg.json --preprocess --verbose > $DATA_DIR/logs/reference/preprocess_kegg.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/kegg.json --load data --verbose --commit > $DATA_DIR/logs/reference/load_kegg.log 2>&1 

# REACTOME
loadResource --config $CONFIG_DIR/reference_databases/reactome.json --load xdbr --verbose --commit > $DATA_DIR/logs/xdbr/load_reactome_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/reactome.json --load data --verbose --commit > $DATA_DIR/logs/reference/load_reactome.log 2>&1 

loadResource --config $CONFIG_DIR/reference_databases/reactome_tc.json --load xdbr --verbose --commit > $DATA_DIR/logs/xdbr/load_reactome_tc_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/reactome_tc.json --load data --verbose --commit > $DATA_DIR/logs/reference/load_reactome_tc.log 2>&1 


# =================================================
# REFERENCE BUILD - Ontologies
# =================================================

# EFO -- needed before loading datasets
loadResource --config $CONFIG_DIR/ontologies/efo.json --load xdbr --commit --verbose > $DATA_DIR/logs/xdbr/load_efo_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/efo.json --load data --commit --verbose > $DATA_DIR/logs/ontologies/load_efo.log 2>&1

# UBERON
loadResource --config $CONFIG_DIR/ontologies/uberon.json --load xdbr --commit --verbose > $DATA_DIR/logs/xdbr/load_uberon_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/uberon.json --load data --commit --verbose > $DATA_DIR/logs/ontologies/load_uberon.log 2>&1

# OBI
loadResource --config $CONFIG_DIR/ontologies/obi.json --load xdbr --commit --verbose > $DATA_DIR/logs/xdbr/load_obi_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/obi.json --load data --commit --verbose > $DATA_DIR/logs/ontologies/load_obi.log 2>&1

# PRO
loadResource --config $CONFIG_DIR/ontologies/pro.json --load xdbr --commit --verbose > $DATA_DIR/logs/xdbr/load_pro_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/pro.json --load data --commit --verbose > $DATA_DIR/logs/ontologies/load_pro.log 2>&1

# HANCESTRO
loadResource --config $CONFIG_DIR/ontologies/hancestro.json --load xdbr --commit --verbose > $DATA_DIR/logs/xdbr/load_hancestro_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/hancestro.json --load data --commit --verbose > $DATA_DIR/logs/ontologies/load_hancestro.log 2>&1


# BRENDA / BTO
loadResource --config $CONFIG_DIR/ontologies/brenda.json --load xdbr --commit --verbose > $DATA_DIR/logs/xdbr/load_brenda_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/brenda.json --load data --commit --verbose > $DATA_DIR/logs/ontologies/load_brenda.log 2>&1

# NCIT OBO Version
loadResource --config $CONFIG_DIR/ontologies/ncit.json --load xdbr --commit --verbose > $DATA_DIR/logs/xdbr/load_ncit_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/ncit.json --load data --commit --verbose > $DATA_DIR/logs/ontologies/load_ncit.log 2>&1

# NCBI Taxon as an Ontology
loadResource --config $CONFIG_DIR/ontologies/taxon.json --load xdbr --commit --verbose > $DATA_DIR/logs/xdbr/load_taxon_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/taxon.json --load data --commit --verbose > $DATA_DIR/logs/ontologies/load_taxon.log 2>&1


# =================================================
# REFERENCE BUILD - dbSNP Variants
# =================================================

# Variants from VEP Results
loadResource --config $CONFIG_DIR/reference_databases/dbsnp.json --load xdbr --verbose --commit > $DATA_DIR/logs/xdbr/load_dbsnp_xdbr.log 2>&1

# skip load vcf & cadd
loadResource --config $CONFIG_DIR/reference_databases/dbsnp.json --load data --verbose --commit > $DATA_DIR/logs/reference/load_dbsnp.log 2>&1

# skip load vep & cadd 
loadResource --config $CONFIG_DIR/reference_databases/dbsnp.json --load data --verbose --commit > $DATA_DIR/logs/reference/load_dbsnp_vcf.log 2>&1

# skip load vcf & vep
loadResource --config $CONFIG_DIR/reference_databases/dbsnp.json --load data --verbose --commit > $DATA_DIR/logs/reference/load_dbsnp_cadd.log 2>&1

# Variants not annotated from VEP

# Merges
loadResource --config $CONFIG_DIR/reference_databases/dbsnp_merge.json --load xdbr --verbose --commit > $DATA_DIR/logs/xdbr/load_dbsnp_merge_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/dbsnp_merge.json --preprocess --verbose > $DATA_DIR/logs/reference/preprocess_dbsnp_merge.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/dbsnp_merge.json --load data --verbose --commit > $DATA_DIR/logs/reference/load_dbsnp_merge.log 2>&1

# =================================================
# ADSP 17K
# =================================================

# variants

loadResource --config $CONFIG_DIR/adsp/17K_annotation.json --load xdbr --verbose --commit > $DATA_DIR/logs/xdbr/load_adsp_17K_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/adsp/17K_annotation.json --load data --verbose --commit > $DATA_DIR/logs/data/load_adsp_17K_vep.log 2>&1 # skip cadd & qc
loadResource --config $CONFIG_DIR/adsp/17K_annotation.json --load data --verbose --commit > $DATA_DIR/logs/data/load_adsp_17K_cadd.log 2>&1 # skip vep & qc
loadResource --config $CONFIG_DIR/adsp/17K_annotation.json --load data --verbose --commit > $DATA_DIR/logs/data/load_adsp_17K_qc.log 2>&1 # skip vep & cadd

# LD

loadResource --config $CONFIG_DIR/adsp/17K_LD.json --preprocess --verbose --commit > $DATA_DIR/logs/data/load_adsp_17K_ld_placeholder.log 2>&1
loadResource --config $CONFIG_DIR/adsp/17K_LD.json --load data --params '{"onlyChr":"1,12,13"}' --verbose --commit > $DATA_DIR/logs/data/load_adsp_17K_ld_part1.log 2>&1
loadResource --config $CONFIG_DIR/adsp/17K_LD.json --load data --params '{"onlyChr":"2,11,14"}' --verbose --commit > $DATA_DIR/logs/data/load_adsp_17K_ld_part2.log 2>&1
loadResource --config $CONFIG_DIR/adsp/17K_LD.json --load data --params '{"onlyChr":"3,10,15"}' --verbose --commit > $DATA_DIR/logs/data/load_adsp_17K_ld_part3.log 2>&1
loadResource --config $CONFIG_DIR/adsp/17K_LD.json --load data --params '{"onlyChr":"4,9,16,19"}' --verbose --commit > $DATA_DIR/logs/data/load_adsp_17K_ld_part4.log 2>&1
loadResource --config $CONFIG_DIR/adsp/17K_LD.json --load data --params '{"onlyChr":"5,8,17,20"}' --verbose --commit > $DATA_DIR/logs/data/load_adsp_17K_ld_part5.log 2>&1
loadResource --config $CONFIG_DIR/adsp/17K_LD.json --load data --params '{"onlyChr":"6,7,18,21"}' --verbose --commit > $DATA_DIR/logs/data/load_adsp_17K_ld_part6.log 2>&1

# =================================================
# 1000 Genomes LD
# =================================================

loadResource --config $CONFIG_DIR/analyses/ld.json --load xdbr --verbose --commit > $DATA_DIR/logs/xdbr/load_ld.log 2>&1

#skip convert & run ld
loadResource --config $CONFIG_DIR/analyses/ld.json --preprocess --verbose > $DATA_DIR/logs/data/ld_extract_samples.log 2>&1
#skip extract & run ld
loadResource --config $CONFIG_DIR/analyses/ld.json --preprocess --verbose > $DATA_DIR/logs/data/ld_convert_vcf.log 2>&1
#skip extract & convert
loadResource --config $CONFIG_DIR/analyses/ld.json --preprocess --verbose > $DATA_DIR/logs/data/ld_run.log 2>&1
#load - skip loading plugin
loadResource --config $CONFIG_DIR/analyses/ld.json --load data --verbose --commit > $DATA_DIR/logs/data/load_ld_placeholders.log 2>&1
#load - skip loading placeholders
loadResource --config $CONFIG_DIR/analyses/ld.json --load data --verbose --commit > $DATA_DIR/logs/data/load_ld.log 2>&1

# =================================================
# NHGRI EBI-EMBL GWAS Catalog
# =================================================

loadResource -c $CONFIG_DIR/reference_databases/gwas_catalog.json --load xdbr --verbose --commit > $DATA_DIR/logs/xdbr/load_nhgri_gc_xdbr.log 2>&1
loadResource -c $CONFIG_DIR/reference_databases/gwas_catalog.json --preprocess --commit --verbose > $DATA_DIR/logs/reference/nhgri_gc_placeholders.log 2>&1 # skip generate
loadResource -c $CONFIG_DIR/reference_databases/gwas_catalog.json --preprocess --verbose > $DATA_DIR/logs/reference/generate_load_nhgri_gc.log 2>&1 # skip skip pan

# run proprocess in test mode to work out issues w/preprocessing and then manually edit/remove any variants that should not be annotated as novel
loadResource -c $CONFIG_DIR/reference_databases/gwas_catalog.json --load data --params '{"test":"true", "preprocess":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/reference/preprocess_test_nhgri_gc.log 2>&1

# skip loading missing / too many issues
# loadResource -c $CONFIG_DIR/reference_databases/gwas_catalog.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/reference/preprocess_nhgri_gc.log 2>&1

loadResource -c $CONFIG_DIR/reference_databases/gwas_catalog.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/reference/load_nhgri_gc.log 2>&1



# =================================================
# ADVP
# =================================================

loadResource -c $CONFIG_DIR/reference_databases/advp.json --load xdbr --verbose --commit > $DATA_DIR/logs/xdbr/advp_xdbr.log 2>&1
loadResource -c $CONFIG_DIR/reference_databases/advp.json --preprocess --commit --verbose > $DATA_DIR/logs/reference/advp_placeholders.log 2>&1 # skip generate
loadResource -c $CONFIG_DIR/reference_databases/advp.json --preprocess --verbose > $DATA_DIR/logs/reference/generate_load_advp.log 2>&1 # skip skip pan

# run proprocess in test mode to work out issues w/preprocessing and then manually edit/remove any variants that should not be annotated as novel
loadResource -c $CONFIG_DIR/reference_databases/advp.json --load data --params '{"test":"true", "preprocess":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/reference/preprocess_test_advp.log 2>&1

# skip loading missing / too many issues
# loadResource -c $CONFIG_DIR/reference_databases/advp.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/reference/preprocess_advp.log 2>&1

loadResource -c $CONFIG_DIR/reference_databases/advp.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/reference/load_advp.log 2>&1


# =================================================
# Summary Statistics
# =================================================

# external db before first load
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json --load xdbr --verbose --commit > $DATA_DIR/logs/xdbr/load_NIAGADS_DATASET_xdbr.log 2>&1
# should be the same in all the config files for NIAGADS accessions, so don't need to run again


# NG00027

mkdir $DATA_DIR/logs/datasets/NG00027
gunzip $NIAGADS_GWAS_DIR/NG00027/GRCh37/*.dat.gz
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00027/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00027/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00027/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00027/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00027/GRCh37_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00027/GRCh38_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00027/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00027/GRCh38_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json  --load data --params '{"genomeBuild":"GRCh37", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00027/GRCh37_archive.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00027/GRCh38_archive.log 2>&1
gzip $NIAGADS_GWAS_DIR/NG00027/GRCh37/*.dat
gzip $DATA_DIR/logs/datasets/NG00027/*.log

tar -zcvf GRCh37.tar.gz --directory $NIAGADS_GWAS_DIR/NG00027 GRCh37 
tar -zcvf GRCh38.tar.gz --directory $NIAGADS_GWAS_DIR/NG00027 GRCh38
rm -r $NIAGADS_GWAS_DIR/NG00027/GRCh37
rm -r $NIAGADS_GWAS_DIR/NG00027/GRCh38


# NG00036

mkdir $DATA_DIR/logs/datasets/NG00036
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00036.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00036/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00036.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00036/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00036.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00036/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00036.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00036/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00036.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00036/GRCh37_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00036.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00036/GRCh38_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00036.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose  > $DATA_DIR/logs/datasets/NG00036/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00036.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose  > $DATA_DIR/logs/datasets/NG00036/GRCh38_standardize.log 2>&1

loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00036.json  --load data --params '{"genomeBuild":"GRCh37", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00036/GRCh37_archive.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00036.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00036/GRCh38_archive.log 2>&1
gzip $NIAGADS_GWAS_DIR/NG00036/GRCh37/*.txt
gzip $DATA_DIR/logs/datasets/NG00036/*.log

tar -zcvf GRCh37.tar.gz --directory $NIAGADS_GWAS_DIR/NG00036 GRCh37 
tar -zcvf GRCh38.tar.gz --directory $NIAGADS_GWAS_DIR/NG00036 GRCh38
rm -r $NIAGADS_GWAS_DIR/NG00036/GRCh37
rm -r $NIAGADS_GWAS_DIR/NG00036/GRCh38



# NG00039

mkdir $DATA_DIR/logs/datasets/NG00039
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00039.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00039/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00039.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00039/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00039.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00039/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00039.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00039/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00039.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00039/GRCh37_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00039.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00039/GRCh38_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00039.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00039/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00039.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00039/GRCh38_standardize.log 2>&1

loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00039.json  --load data --params '{"genomeBuild":"GRCh37", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00039/GRCh37_archive.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00039.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00039/GRCh38_archive.log 2>&1
gzip $NIAGADS_GWAS_DIR/NG00039/GRCh37/*.txt
gzip $DATA_DIR/logs/datasets/NG00039/*.log

tar -zcvf GRCh37.tar.gz --directory $NIAGADS_GWAS_DIR/NG00039 GRCh37 
tar -zcvf GRCh38.tar.gz --directory $NIAGADS_GWAS_DIR/NG00039 GRCh38
rm -r $NIAGADS_GWAS_DIR/NG00039/GRCh37
rm -r $NIAGADS_GWAS_DIR/NG00039/GRCh38

# NG00040

mkdir $DATA_DIR/logs/datasets/NG00040
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00040.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00040/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00040.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00040/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00040.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00040/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00040.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00040/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00040.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00040/GRCh37_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00040.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00040/GRCh38_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00040.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00040/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00040.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00040/GRCh38_standardize.log 2>&1

loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00040.json  --load data --params '{"genomeBuild":"GRCh37", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00040/GRCh37_archive.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00040.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00040/GRCh38_archive.log 2>&1
gzip $NIAGADS_GWAS_DIR/NG00040/GRCh37/*.txt
gzip $DATA_DIR/logs/datasets/NG00040/*.log

tar -zcvf GRCh37.tar.gz --directory $NIAGADS_GWAS_DIR/NG00040 GRCh37 
tar -zcvf GRCh38.tar.gz --directory $NIAGADS_GWAS_DIR/NG00040 GRCh38
rm -r $NIAGADS_GWAS_DIR/NG00040/GRCh37
rm -r $NIAGADS_GWAS_DIR/NG00040/GRCh38


# NG00041

mkdir $DATA_DIR/logs/datasets/NG00041
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00041.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00041/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00041.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00041/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00041.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00041/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00041.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00041/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00041.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00041/GRCh37_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00041.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00041/GRCh38_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00041.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00041/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00041.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00041/GRCh38_standardize.log 2>&1

loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00041.json  --load data --params '{"genomeBuild":"GRCh37", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00041/GRCh37_archive.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00041.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00041/GRCh38_archive.log 2>&1
gzip $NIAGADS_GWAS_DIR/NG00041/GRCh37/*.txt
gzip $DATA_DIR/logs/datasets/NG00041/*.log

tar -zcvf GRCh37.tar.gz --directory $NIAGADS_GWAS_DIR/NG00041 GRCh37 
tar -zcvf GRCh38.tar.gz --directory $NIAGADS_GWAS_DIR/NG00041 GRCh38
rm -r $NIAGADS_GWAS_DIR/NG00041/GRCh37
rm -r $NIAGADS_GWAS_DIR/NG00041/GRCh38

# NG00045

mkdir $DATA_DIR/logs/datasets/NG00045
gunzip $NIAGADS_GWAS_DIR/NG00045/GRCh37/hg19_updated_1162017/*.txt.gz
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00045.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00045/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00045.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00045/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00045.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00045/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00045.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00045/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00045.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00045/GRCh37_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00045.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00045/GRCh38_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00045.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00045/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00045.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00045/GRCh38_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00045.json  --load data --params '{"genomeBuild":"GRCh37", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00045/GRCh37_archive.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00045.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00045/GRCh38_archive.log 2>&1
gzip $NIAGADS_GWAS_DIR/NG00045/GRCh37/hg19_updated_1162017/*.txt
gzip $DATA_DIR/logs/datasets/NG00045/*.log

tar -zcvf GRCh37.tar.gz --directory $NIAGADS_GWAS_DIR/NG00045/hg19_updated_1162017 GRCh37 
tar -zcvf GRCh38.tar.gz --directory $NIAGADS_GWAS_DIR/NG00045/hg19_updated_1162017 GRCh38
rm -r $NIAGADS_GWAS_DIR/NG00045/hg19_updated_1162017/GRCh37
rm -r $NIAGADS_GWAS_DIR/NG00045/hg19_updated_1162017/GRCh38

# NG00048

mkdir $DATA_DIR/logs/datasets/NG00048
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00048.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00048/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00048.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00048/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00048.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00048/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00048.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00048/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00048.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00048/GRCh37_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00048.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00048/GRCh38_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00048.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00048/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00048.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00048/GRCh38_standardize.log 2>&1

loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00048.json  --load data --params '{"genomeBuild":"GRCh37", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00048/GRCh37_archive.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00048.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00048/GRCh38_archive.log 2>&1
gzip $NIAGADS_GWAS_DIR/NG00048/GRCh37/*.meta
gzip $DATA_DIR/logs/datasets/NG00048/*.log

tar -zcvf GRCh37.tar.gz --directory $NIAGADS_GWAS_DIR/NG00048 GRCh37 
tar -zcvf GRCh38.tar.gz --directory $NIAGADS_GWAS_DIR/NG00048 GRCh38
rm -r $NIAGADS_GWAS_DIR/NG00048/GRCh37
rm -r $NIAGADS_GWAS_DIR/NG00048/GRCh38

# NG00049

mkdir $DATA_DIR/logs/datasets/NG00049
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00049.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00049/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00049.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00049/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00049.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00049/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00049.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00049/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00049.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00049/GRCh37_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00049.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00049/GRCh38_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00049.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00049/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00049.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00049/GRCh38_standardize.log 2>&1

loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00049.json  --load data --params '{"genomeBuild":"GRCh37", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00049/GRCh37_archive.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00049.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00049/GRCh38_archive.log 2>&1
gzip $NIAGADS_GWAS_DIR/NG00049/GRCh37/*.txt
gzip $DATA_DIR/logs/datasets/NG00049/*.log

tar -zcvf GRCh37.tar.gz --directory $NIAGADS_GWAS_DIR/NG00049 GRCh37 
tar -zcvf GRCh38.tar.gz --directory $NIAGADS_GWAS_DIR/NG00049 GRCh38
rm -r $NIAGADS_GWAS_DIR/NG00049/GRCh37
rm -r $NIAGADS_GWAS_DIR/NG00049/GRCh38

# NG00052

mkdir $DATA_DIR/logs/datasets/NG00052
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00052.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00052/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00052.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00052/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00052.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00052/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00052.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00052/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00052.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00052/GRCh37_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00052.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00052/GRCh38_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00052.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00052/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00052.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00052/GRCh38_standardize.log 2>&1

loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00052.json  --load data --params '{"genomeBuild":"GRCh37", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00052/GRCh37_archive.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00052.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00052/GRCh38_archive.log 2>&1
gzip $NIAGADS_GWAS_DIR/NG00052/GRCh37/*.txt
gzip $DATA_DIR/logs/datasets/NG00052/*.log

tar -zcvf GRCh37.tar.gz --directory $NIAGADS_GWAS_DIR/NG00052 GRCh37 
tar -zcvf GRCh38.tar.gz --directory $NIAGADS_GWAS_DIR/NG00052 GRCh38
rm -r $NIAGADS_GWAS_DIR/NG00052/GRCh37
rm -r $NIAGADS_GWAS_DIR/NG00052/GRCh38

# NG00053

mkdir $DATA_DIR/logs/datasets/NG00053
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00053.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00053/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00053.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00053/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00053.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00053/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00053.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00053/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00053.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00053/GRCh37_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00053.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00053/GRCh38_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00053.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00053/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00053.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00053/GRCh38_standardize.log 2>&1

loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00053.json  --load data --params '{"genomeBuild":"GRCh37", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00053/GRCh37_archive.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00053.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00053/GRCh38_archive.log 2>&1
gzip $NIAGADS_GWAS_DIR/NG00053/GRCh37/*.TBL
gzip $DATA_DIR/logs/datasets/NG00053/*.log

tar -zcvf GRCh37.tar.gz --directory $NIAGADS_GWAS_DIR/NG00053 GRCh37 
tar -zcvf GRCh38.tar.gz --directory $NIAGADS_GWAS_DIR/NG00053 GRCh38
rm -r $NIAGADS_GWAS_DIR/NG00053/GRCh37
rm -r $NIAGADS_GWAS_DIR/NG00053/GRCh38

# NG00055

mkdir $DATA_DIR/logs/datasets/NG00055
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00055.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00055/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00055.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00055/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00055.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00055/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00055.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00055/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00055.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00055/GRCh37_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00055.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00055/GRCh38_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00055.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00055/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00055.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00055/GRCh38_standardize.log 2>&1

loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00055.json  --load data --params '{"genomeBuild":"GRCh37", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00055/GRCh37_archive.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00055.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00055/GRCh38_archive.log 2>&1
gzip $NIAGADS_GWAS_DIR/NG00055/GRCh37/*.txt
gzip $DATA_DIR/logs/datasets/NG00055/*.log

tar -zcvf GRCh37.tar.gz --directory $NIAGADS_GWAS_DIR/NG00055 GRCh37 
tar -zcvf GRCh38.tar.gz --directory $NIAGADS_GWAS_DIR/NG00055 GRCh38
rm -r $NIAGADS_GWAS_DIR/NG00055/GRCh37
rm -r $NIAGADS_GWAS_DIR/NG00055/GRCh38

# NG00056

mkdir $DATA_DIR/logs/datasets/NG00056
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00056.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00056/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00056.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00056/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00056.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00056/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00056.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00056/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00056.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00056/GRCh37_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00056.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00056/GRCh38_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00056.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00056/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00056.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00056/GRCh38_standardize.log 2>&1

loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00056.json  --load data --params '{"genomeBuild":"GRCh37", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00056/GRCh37_archive.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00056.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00056/GRCh38_archive.log 2>&1
gzip $NIAGADS_GWAS_DIR/NG00056/GRCh37/*.tbx
gzip $DATA_DIR/logs/datasets/NG00056/*.log

tar -zcvf GRCh37.tar.gz --directory $NIAGADS_GWAS_DIR/NG00056 GRCh37 
tar -zcvf GRCh38.tar.gz --directory $NIAGADS_GWAS_DIR/NG00056 GRCh38
rm -r $NIAGADS_GWAS_DIR/NG00056/GRCh37
rm -r $NIAGADS_GWAS_DIR/NG00056/GRCh38

# NG00058

mkdir $DATA_DIR/logs/datasets/NG00058
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00058.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00058/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00058.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00058/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00058.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00058/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00058.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00058/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00058.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00058/GRCh37_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00058.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00058/GRCh38_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00058.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00058/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00058.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00058/GRCh38_standardize.log 2>&1

loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00058.json  --load data --params '{"genomeBuild":"GRCh37", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00058/GRCh37_archive.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00058.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00058/GRCh38_archive.log 2>&1
gzip $NIAGADS_GWAS_DIR/NG00058/GRCh37/*.txt
gzip $DATA_DIR/logs/datasets/NG00058/*.log

tar -zcvf GRCh37.tar.gz --directory $NIAGADS_GWAS_DIR/NG00058 GRCh37 
tar -zcvf GRCh38.tar.gz --directory $NIAGADS_GWAS_DIR/NG00058 GRCh38
rm -r $NIAGADS_GWAS_DIR/NG00058/GRCh37
rm -r $NIAGADS_GWAS_DIR/NG00058/GRCh38


# NOTE: of NG00073, NG00075, NG00076 must load NG00075 first to have reference against which to check gapped INDELS

# NG00075

mkdir $DATA_DIR/logs/datasets/NG00075
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00075.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00075/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00075.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00075/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00075.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00075/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00075.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00075/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00075.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00075/GRCh37_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00075.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00075/GRCh38_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00075.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00075/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00075.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00075/GRCh38_standardize.log 2>&1

loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00075.json  --load data --params '{"genomeBuild":"GRCh37", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00075/GRCh37_archive.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00075.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00075/GRCh38_archive.log 2>&1
gzip $NIAGADS_GWAS_DIR/NG00075/GRCh37/*.txt
gzip $DATA_DIR/logs/datasets/NG00075/*.log

tar -zcvf GRCh37.tar.gz --directory $NIAGADS_GWAS_DIR/NG00075 GRCh37 
tar -zcvf GRCh38.tar.gz --directory $NIAGADS_GWAS_DIR/NG00075 GRCh38
rm -r $NIAGADS_GWAS_DIR/NG00075/GRCh37
rm -r $NIAGADS_GWAS_DIR/NG00075/GRCh38


# NG00073

mkdir $DATA_DIR/logs/datasets/NG00073
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00073.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00073/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00073.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00073/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00073.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00073/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00073.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00073/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00073.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00073/GRCh37_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00073.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00073/GRCh38_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00073.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00073/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00073.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00073/GRCh38_standardize.log 2>&1

loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00073.json  --load data --params '{"genomeBuild":"GRCh37", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00073/GRCh37_archive.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00073.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00073/GRCh38_archive.log 2>&1
gzip $NIAGADS_GWAS_DIR/NG00073/GRCh37/*.txt
gzip $DATA_DIR/logs/datasets/NG00073/*.log

tar -zcvf GRCh37.tar.gz --directory $NIAGADS_GWAS_DIR/NG00073 GRCh37 
tar -zcvf GRCh38.tar.gz --directory $NIAGADS_GWAS_DIR/NG00073 GRCh38
rm -r $NIAGADS_GWAS_DIR/NG00073/GRCh37
rm -r $NIAGADS_GWAS_DIR/NG00073/GRCh38


# NG00076

mkdir $DATA_DIR/logs/datasets/NG00076
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00076.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00076/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00076.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00076/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00076.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00076/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00076.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00076/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00076.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00076/GRCh37_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00076.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00076/GRCh38_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00076.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00076/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00076.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00076/GRCh38_standardize.log 2>&1

loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00076.json  --load data --params '{"genomeBuild":"GRCh37", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00076/GRCh37_archive.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00076.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00076/GRCh38_archive.log 2>&1
gzip $NIAGADS_GWAS_DIR/NG00076/GRCh37/*.txt
gzip $DATA_DIR/logs/datasets/NG00076/*.log

tar -zcvf GRCh37.tar.gz --directory $NIAGADS_GWAS_DIR/NG00076 GRCh37 
tar -zcvf GRCh38.tar.gz --directory $NIAGADS_GWAS_DIR/NG00076 GRCh38
rm -r $NIAGADS_GWAS_DIR/NG00076/GRCh37
rm -r $NIAGADS_GWAS_DIR/NG00076/GRCh38

# NG00078

mkdir $DATA_DIR/logs/datasets/NG00078
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00078.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00078/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00078.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00078/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00078.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00078/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00078.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00078/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00078.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00078/GRCh37_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00078.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00078/GRCh38_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00078.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00078/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00078.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00078/GRCh38_standardize.log 2>&1

loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00078.json  --load data --params '{"genomeBuild":"GRCh37", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00078/GRCh37_archive.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00078.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00078/GRCh38_archive.log 2>&1
gzip $NIAGADS_GWAS_DIR/NG00078/GRCh37/*.txt
gzip $DATA_DIR/logs/datasets/NG00078/*.log

tar -zcvf GRCh37.tar.gz --directory $NIAGADS_GWAS_DIR/NG00078 GRCh37 
tar -zcvf GRCh38.tar.gz --directory $NIAGADS_GWAS_DIR/NG00078 GRCh38
rm -r $NIAGADS_GWAS_DIR/NG00078/GRCh37
rm -r $NIAGADS_GWAS_DIR/NG00078/GRCh38

# NG00115

mkdir $DATA_DIR/logs/datasets/NG00115
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00115.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00115/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00115.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00115/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00115.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00115/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00115.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00115/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00115.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00115/GRCh37_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00115.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00115/GRCh38_update.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00115.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00115/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00115.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00115/GRCh38_standardize.log 2>&1

loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00115.json  --load data --params '{"genomeBuild":"GRCh37", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00115/GRCh37_archive.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00115.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00115/GRCh38_archive.log 2>&1
gzip $NIAGADS_GWAS_DIR/NG00115/GRCh37/*.txt
gzip $DATA_DIR/logs/datasets/NG00115/*.log

tar -zcvf GRCh37.tar.gz --directory $NIAGADS_GWAS_DIR/NG00115 GRCh37 
tar -zcvf GRCh38.tar.gz --directory $NIAGADS_GWAS_DIR/NG00115 GRCh38
rm -r $NIAGADS_GWAS_DIR/NG00115/GRCh37
rm -r $NIAGADS_GWAS_DIR/NG00115/GRCh38

# NG00122

mkdir $DATA_DIR/logs/datasets/NG00122
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00122.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00122/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00122.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00122/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00122.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00122/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00122.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00122/GRCh38_standardize.log 2>&1

loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00122.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00122/GRCh38_archive.log 2>&1
gzip $SHARED_DATA_DIR/NIAGADS/GRCh38/NG00122/GRCh38/*.txt
gzip $DATA_DIR/logs/datasets/NG00122/*.log

tar -zcvf GRCh38.tar.gz --directory $SHARED_DATA_DIR/NIAGADS/GRCh38/NG00122 GRCh38
rm -r $SHARED_DATA_DIR/NIAGADS/GRCh38/NG00122/GRCh38


#### FILER Genome Browser Tracks

ga GenomicsDBData::Load::Plugin::LoadFILERTrack --filerUri https://tf.lisanwanglab.org/FILER/get_metadata.php --genomeBuild hg38 --loadTrackMetadata --fileDir $DATA_DIR/FILER --extDbRlsSpec "FILER|current-GRCh38" --dataSource ENCODE_roadmap --commit > $DATA_DIR/logs/FILER/ENCODE_roadmap.log 2>&1
ga GenomicsDBData::Load::Plugin::LoadFILERTrack --filerUri https://tf.lisanwanglab.org/FILER/get_metadata.php --genomeBuild hg38 --loadTrackMetadata --fileDir $DATA_DIR/FILER --extDbRlsSpec "FILER|current-GRCh38" --dataSource ENCODE --commit > $DATA_DIR/logs/FILER/ENCODE.log 2>&1
ga GenomicsDBData::Load::Plugin::LoadFILERTrack --filerUri https://tf.lisanwanglab.org/FILER/get_metadata.php --genomeBuild hg38 --loadTrackMetadata --fileDir $DATA_DIR/FILER --extDbRlsSpec "FILER|current-GRCh38" --dataSource GTEx_v8 --commit  > $DATA_DIR/logs/FILER/GTex_v8.log 2>&1

#### LocusZoom Tracks

# recombination
loadResource -c $CONFIG_DIR/tracks/lz_recombination.json --load xdbr --commit > $DATA_DIR/logs/xdbr/load_recomb_xdbr.log 2>&1
loadResource -c $CONFIG_DIR/tracks/lz_recombination.json --preprocess --commit > $DATA_DIR/logs/reference/load_recomb_placeholders.log 2>&1
loadResource -c $CONFIG_DIR/tracks/lz_recombination.json --load data --commit > $DATA_DIR/logs/reference/load_recomb.log 2>&1

# gnomAD gene constraint (required or gene tracks will fail)



#### FILER GeneOverlap POC / brain only

ga GenomicsDBData::Load::Plugin::LoadGeneFeatureOverlapResult --filerUri https://tf.lisanwanglab.org/FILER/ --genomeBuild hg38 --extDbRlsSpec "FILER|current-GRCh38"  --requestSize 500 --tracks NGEN024629,NGEN024636,NGEN024640,NGEN024682,NGEN024761,NGEN024805,NGEN024854,NGEN024890,NGEN024961,NGEN025037,NGEN025043,NGEN025056,NGEN025135,NGEN025159,NGEN025173,NGEN025241,NGEN025270,NGEN025271,NGEN025299,NGEN025343,NGEN025355,NGEN025419,NGEN025442,NGEN025519,NGEN025519F,NGEN025527,NGEN025613,NGEN025625,NGEN025646,NGEN025646F,NGEN025667,NGEN025677,NGEN025693,NGEN025708,NGEN025712,NGEN025755,NGEN025760,NGEN025795,NGEN025870,NGEN025881,NGEN025882,NGEN025886,NGEN025896,NGEN026013,NGEN026075,NGEN026110,NGEN026198,NGEN026236,NGEN026250,NGEN026348,NGEN026360,NGEN026362,NGEN026443,NGEN026510,NGEN026631,NGEN026656,NGEN026750,NGEN026823,NGEN026925,NGEN026934,NGEN027016,NGEN027027,NGEN027096,NGEN027206,NGEN027361,NGEN027409,NGEN027479,NGEN027483,NGEN027516,NGEN027523,NGEN027529,NGEN027598,NGEN027683,NGEN027683F,NGEN027739,NGEN027752,NGEN027773,NGEN027777,NGEN027805,NGEN027884,NGEN027931,NGEN027962,NGEN028041,NGEN028041F,NGEN028045,NGEN028054,NGEN028068,NGEN028076,NGEN028078,NGEN028115,NGEN028165,NGEN028165F,NGEN028282,NGEN028337,NGEN028574,NGEN028604,NGEN028685,NGEN028698,NGEN028742,NGEN028785,NGEN028789,NGEN028805,NGEN028830,NGEN028850,NGEN028875,NGEN028881,NGEN028885,NGEN028888,NGEN028974,NGEN029002,NGEN029059,NGEN029138,NGEN029156,NGEN029185,NGEN029211,NGEN029309,NGEN029335,NGEN029483,NGEN029487,NGEN029501,NGEN029501F,NGEN029551,NGEN029598,NGEN029697,NGEN029708,NGEN029760,NGEN029770,NGEN029824,NGEN029837,NGEN029962,NGEN029965,NGEN029993,NGEN029994,NGEN030010,NGEN030104,NGEN030138,NGEN030156,NGEN030166,NGEN030213,NGEN030270,NGEN030306,NGEN030375,NGEN012650,NGEN030410,NGEN030421,NGEN030423,NGEN030438,NGEN030456,NGEN030526,NGEN030592,NGEN030762,NGEN030763,NGEN030881,NGEN030914,NGEN031101,NGEN031109,NGEN031148,NGEN031161,NGEN031172,NGEN031190,NGEN031208,NGEN031219,NGEN031254,NGEN031277,NGEN031298,NGEN031303,NGEN031337,NGEN031353,NGEN031369,NGEN031399,NGEN031404,NGEN031426,NGEN031508,NGEN031640,NGEN031647,NGEN031653,NGEN031752,NGEN031759,NGEN031777,NGEN031796,NGEN031881,NGEN031927,NGEN031969,NGEN031978,NGEN032013,NGEN032023,NGEN032032,NGEN032120,NGEN032324,NGEN032340,NGEN032396,NGEN032400,NGEN032400F,NGEN032458,NGEN032528,NGEN032575,NGEN032662,NGEN032674,NGEN032686,NGEN032703,NGEN032723,NGEN032749,NGEN032787,NGEN032867,NGEN032923,NGEN032980,NGEN032987,NGEN033068,NGEN033103,NGEN033148,NGEN033210,NGEN033299,NGEN033360,NGEN033405,NGEN033463,NGEN033491,NGEN001526,NGEN033591,NGEN001655,NGEN033748,NGEN033754,NGEN033784,NGEN033805,NGEN033825,NGEN033852,NGEN033922,NGEN033923,NGEN033963,NGEN033990,NGEN034007,NGEN034021,NGEN034095,NGEN034103,NGEN034141,NGEN034145,NGEN034187,NGEN034188,NGEN034241,NGEN034257,NGEN034303,NGEN034388,NGEN034391,NGEN034414,NGEN034536,NGEN034558,NGEN034592,NGEN034645,NGEN034690,NGEN034701,NGEN034716,NGEN034724,NGEN034863,NGEN034927,NGEN034993,NGEN035012,NGEN035026,NGEN035030,NGEN035082,NGEN035111,NGEN035172,NGEN035227,NGEN035365,NGEN035396,NGEN035408,NGEN035487,NGEN035526,NGEN035532,NGEN035665,NGEN000484,NGEN000484F,NGEN000489,NGEN000561,NGEN000561F,NGEN000583,NGEN000584,NGEN000584F,NGEN000705,NGEN000734,NGEN000736,NGEN000755,NGEN000765,NGEN000792,NGEN000792F,NGEN000793,NGEN000809,NGEN000809F,NGEN000832,NGEN000848,NGEN000882,NGEN000967,NGEN001076,NGEN001148,NGEN001198,NGEN001250,NGEN001271,NGEN001288,NGEN001355,NGEN001363,NGEN001363F,NGEN001436,NGEN001436F,NGEN001452,NGEN001454,NGEN001454F,NGEN001494,NGEN001512,NGEN001563,NGEN001563F,NGEN001573,NGEN001575,NGEN001590,NGEN001603,NGEN001603F,NGEN001636,NGEN001665,NGEN001665F,NGEN001681,NGEN001709,NGEN001737,NGEN001726,NGEN001770,NGEN001790,NGEN001812,NGEN001812F,NGEN001816,NGEN001921,NGEN001977,NGEN001990,NGEN002025,NGEN002063,NGEN002070,NGEN003723,NGEN002104,NGEN002107,NGEN002111,NGEN002136,NGEN002136F,NGEN002222,NGEN002237,NGEN002308,NGEN002312,NGEN002330,NGEN002407,NGEN002426,NGEN002442,NGEN002488,NGEN002491,NGEN002500,NGEN002518,NGEN002518F,NGEN002586,NGEN002551,NGEN002561,NGEN002599,NGEN002602,NGEN002667,NGEN002675,NGEN002678,NGEN002678F,NGEN002689,NGEN002704,NGEN002707,NGEN002713,NGEN002798,NGEN002810,NGEN002831,NGEN002838,NGEN002853,NGEN002857,NGEN002872,NGEN002902,NGEN002910,NGEN002918,NGEN002927,NGEN002933,NGEN008154,NGEN003036,NGEN003054,NGEN003101,NGEN003103,NGEN003124,NGEN003135,NGEN003135F,NGEN003375,NGEN003176,NGEN003177,NGEN003177F,NGEN003194,NGEN003206,NGEN003264,NGEN003365,NGEN003362,NGEN003370,NGEN003375F,NGEN003466,NGEN003468,NGEN003502,NGEN003512,NGEN003531,NGEN003549,NGEN003572,NGEN003681F,NGEN003681,NGEN003684,NGEN003750,NGEN005141,NGEN003890,NGEN003930,NGEN003932,NGEN003943,NGEN003988,NGEN004021,NGEN004048,NGEN004067,NGEN004076,NGEN004094,NGEN004104,NGEN004130,NGEN004147,NGEN004196,NGEN004222,NGEN004227,NGEN004231,NGEN004231F,NGEN004254,NGEN005499,NGEN004288,NGEN004304,NGEN004304F,NGEN004345,NGEN004345F,NGEN004375,NGEN004398,NGEN004398F,NGEN004403,NGEN004424,NGEN004457,NGEN004509,NGEN004512,NGEN004517,NGEN004526,NGEN004630,NGEN004652,NGEN004652F,NGEN004697,NGEN004722,NGEN004722F,NGEN004747,NGEN004772,NGEN004901,NGEN004918,NGEN004918F,NGEN004999,NGEN005044,NGEN005041,NGEN005044F,NGEN005056,NGEN005063,NGEN005073,NGEN005127,NGEN005138,NGEN005153,NGEN005208,NGEN005222,NGEN005257,NGEN005260,NGEN005300,NGEN005358,NGEN005372,NGEN005500,NGEN005459,NGEN005475,NGEN005537,NGEN005563,NGEN005620,NGEN005671,NGEN005780,NGEN005714,NGEN005714F,NGEN005731,NGEN005746,NGEN005750,NGEN005799,NGEN005821,NGEN005869,NGEN005881,NGEN005896,NGEN005917,NGEN005944,NGEN005944F,NGEN005960,NGEN005990,NGEN006109,NGEN006166,NGEN006178,NGEN006219,NGEN006261,NGEN006316,NGEN006328,NGEN006389,NGEN006432,NGEN006456,NGEN006496,NGEN006531,NGEN006541,NGEN006589,NGEN006685,NGEN006685F,NGEN006716,NGEN006775,NGEN006741,NGEN006743,NGEN006743F,NGEN006786,NGEN006814,NGEN006814F,NGEN006834,NGEN006848,NGEN006858,NGEN006864,NGEN006867,NGEN006897,NGEN006989,NGEN006995,NGEN007005,NGEN007035,NGEN007048,NGEN007066,NGEN007081,NGEN007092,NGEN007096,NGEN007163,NGEN007217,NGEN007263,NGEN007314,NGEN007323,NGEN007345,NGEN007359,NGEN007360,NGEN007466,NGEN007466F,NGEN007478,NGEN007514,NGEN007548,NGEN007563,NGEN007563F,NGEN007630,NGEN007630F,NGEN007638,NGEN007661,NGEN007661F,NGEN007672,NGEN007714,NGEN007674,NGEN007788,NGEN007826,NGEN007846,NGEN007867,NGEN007870,NGEN007871,NGEN007872,NGEN008044,NGEN008184,NGEN008254,NGEN008297,NGEN008355,NGEN008393,NGEN008393F,NGEN008414,NGEN008443,NGEN008458,NGEN008791,NGEN008523,NGEN008551,NGEN008586,NGEN008628,NGEN008647,NGEN008714,NGEN008726,NGEN008736,NGEN008813,NGEN008817,NGEN008882,NGEN008882F,NGEN008908,NGEN008938,NGEN008938F,NGEN009082,NGEN009156,NGEN009186,NGEN009290,NGEN009294,NGEN009330,NGEN009330F,NGEN009377,NGEN009377F,NGEN009391,NGEN009413,NGEN009422,NGEN009440,NGEN009459,NGEN009482,NGEN009515,NGEN009527,NGEN009535,NGEN009541,NGEN009541F,NGEN009793,NGEN009636,NGEN009751,NGEN009799,NGEN009855,NGEN009881,NGEN009884,NGEN009903,NGEN010077,NGEN010035,NGEN010079,NGEN010079F,NGEN010096,NGEN010123,NGEN010155,NGEN010243,NGEN010249,NGEN010297,NGEN010308,NGEN010363,NGEN010490,NGEN010422,NGEN010461,NGEN010519,NGEN010519F,NGEN010531,NGEN010572,NGEN010572F,NGEN010583,NGEN010655,NGEN010655F,NGEN010661,NGEN010692,NGEN010699,NGEN010720,NGEN010724,NGEN010730,NGEN010778,NGEN010803,NGEN010855,NGEN010834,NGEN010850,NGEN010851,NGEN010858,NGEN010880,NGEN010896,NGEN010983,NGEN011036,NGEN011046,NGEN011069,NGEN011126,NGEN011146,NGEN011299,NGEN011224,NGEN011243,NGEN011412,NGEN011413,NGEN011413F,NGEN011529,NGEN011560,NGEN011563,NGEN011573,NGEN011619,NGEN011664,NGEN011678,NGEN011700,NGEN011719,NGEN011769,NGEN011796,NGEN011796F,NGEN011828,NGEN011831,NGEN011861,NGEN011970,NGEN011993,NGEN012033,NGEN012055,NGEN012101,NGEN012117,NGEN012172,NGEN012198,NGEN012198F,NGEN012240,NGEN012243,NGEN012243F,NGEN012300,NGEN012300F,NGEN012343,NGEN012359,NGEN012415,NGEN012426,NGEN012437,NGEN012487,NGEN012489,NGEN012489F,NGEN012498,NGEN012547,NGEN012547F,NGEN012586,NGEN012594,NGEN012697,NGEN012713,NGEN012924,NGEN012995,NGEN012995F,NGEN013133,NGEN013186,NGEN013186F,NGEN013253,NGEN013301,NGEN013301F,NGEN013305,NGEN013305F,NGEN013328,NGEN013353,NGEN013363,NGEN013372,NGEN013372F,NGEN013378,NGEN013400,NGEN013444,NGEN013452,NGEN013492,NGEN013495,NGEN013514,NGEN013527,NGEN013570,NGEN013570F,NGEN013602,NGEN013610,NGEN014051,NGEN013626,NGEN013654,NGEN013698,NGEN013713,NGEN013770,NGEN013786,NGEN013822,NGEN013831,NGEN013855,NGEN013893,NGEN013962,NGEN014054,NGEN014101,NGEN014112,NGEN014142,NGEN014231,NGEN014270,NGEN014309,NGEN014324,NGEN014345,NGEN014420,NGEN014426,NGEN014468,NGEN014491,NGEN014519,NGEN014552,NGEN014552F,NGEN014579,NGEN014979,NGEN014615,NGEN014672,NGEN014729,NGEN014839,NGEN014925,NGEN014955,NGEN015067,NGEN015151,NGEN015156,NGEN015162,NGEN015165,NGEN015165F,NGEN015182,NGEN015187,NGEN015226,NGEN015248,NGEN015276,NGEN015284,NGEN015301,NGEN015327,NGEN015353,NGEN015365,NGEN015434,NGEN015458,NGEN015501,NGEN015579,NGEN015580,NGEN015589,NGEN015664,NGEN015672,NGEN015694,NGEN015749,NGEN015753,NGEN015769,NGEN015821,NGEN024717,NGEN024952,NGEN025431,NGEN025467,NGEN025516,NGEN026010,NGEN026040,NGEN026268,NGEN026457,NGEN026546,NGEN026563,NGEN026575,NGEN026732,NGEN026789,NGEN026819,NGEN026896,NGEN027067,NGEN027160,NGEN027749,NGEN028102,NGEN028505,NGEN028935,NGEN029177,NGEN029383,NGEN029444,NGEN029746,NGEN029927,NGEN030360,NGEN031325,NGEN031390,NGEN031471,NGEN032171,NGEN032274,NGEN032437,NGEN032862,NGEN033141,NGEN033676,NGEN033997,NGEN034174,NGEN034378,NGEN034385,NGEN034397,NGEN034524,NGEN034721,NGEN035294,NGEN035294F,NGEN035328,NGGT000242,NGGT000235,NGGT000236,NGGT000237,NGGT000238,NGGT000239,NGGT000240,NGGT000241,NGGT000243,NGGT000244,NGGT000245,NGGT000246,NGGT000247,NGGT000284,NGGT000285,NGGT000286,NGGT000287,NGGT000288,NGGT000289,NGGT000290,NGGT000291,NGGT000292,NGGT000293,NGGT000294,NGGT000295,NGGT000296,NGGT000333,NGGT000334,NGGT000335,NGGT000336,NGGT000337,NGGT000338,NGGT000339,NGGT000340,NGGT000341,NGGT000342,NGGT000343,NGGT000344,NGGT000345,NGGT000382,NGGT000383,NGGT000384,NGGT000385,NGGT000386,NGGT000387,NGGT000388,NGGT000389,NGGT000390,NGGT000391,NGGT000392,NGGT000393,NGGT000394 --commit > $LOG_FILE_DIR/FILER/load_gene_brain_overlaps.log 2>&1

# temp chr19
ga GenomicsDBData::Load::Plugin::LoadGeneFeatureOverlapResult --filerUri https://tf.lisanwanglab.org/FILER/ --chromosome chr19 --genomeBuild hg38 --extDbRlsSpec "FILER|current-GRCh38"  --requestSize 50 --tracks NGEN024629,NGEN024636,NGEN024640,NGEN024682,NGEN024761,NGEN024805,NGEN024854,NGEN024890,NGEN024961,NGEN025037,NGEN025043,NGEN025056,NGEN025135,NGEN025159,NGEN025173,NGEN025241,NGEN025270,NGEN025271,NGEN025299,NGEN025343,NGEN025355,NGEN025419,NGEN025442,NGEN025519,NGEN025527,NGEN025613,NGEN025625,NGEN025646,NGEN025667,NGEN025677,NGEN025693,NGEN025708,NGEN025712,NGEN025755,NGEN025760,NGEN025795,NGEN025870,NGEN025881,NGEN025882,NGEN025886,NGEN025896,NGEN026013,NGEN026075,NGEN026110,NGEN026198,NGEN026236,NGEN026250,NGEN026348,NGEN026360,NGEN026362,NGEN026443,NGEN026510,NGEN026631,NGEN026656,NGEN026750,NGEN026823,NGEN026925,NGEN026934,NGEN027016,NGEN027027,NGEN027096,NGEN027206,NGEN027361,NGEN027409,NGEN027479,NGEN027483,NGEN027516,NGEN027523,NGEN027529,NGEN027598,NGEN027683,NGEN027739,NGEN027752,NGEN027773,NGEN027777,NGEN027805,NGEN027884,NGEN027931,NGEN027962,NGEN028041,NGEN028045,NGEN028054,NGEN028068,NGEN028076,NGEN028078,NGEN028115,NGEN028165,NGEN028282,NGEN028337,NGEN028574,NGEN028604,NGEN028685,NGEN028698,NGEN028742,NGEN028785,NGEN028789,NGEN028805,NGEN028830,NGEN028850,NGEN028875,NGEN028881,NGEN028885,NGEN028888,NGEN028974,NGEN029002,NGEN029059,NGEN029138,NGEN029156,NGEN029185,NGEN029211,NGEN029309,NGEN029335,NGEN029483,NGEN029487,NGEN029501,NGEN029551,NGEN029598,NGEN029697,NGEN029708,NGEN029760,NGEN029770,NGEN029824,NGEN029837,NGEN029962,NGEN029965,NGEN029993,NGEN029994,NGEN030010,NGEN030104,NGEN030138,NGEN030156,NGEN030166,NGEN030213,NGEN030270,NGEN030306,NGEN030375,NGEN012650,NGEN030410,NGEN030421,NGEN030423,NGEN030438,NGEN030456,NGEN030526,NGEN030592,NGEN030762,NGEN030763,NGEN030881,NGEN030914,NGEN031101,NGEN031109,NGEN031148,NGEN031161,NGEN031172,NGEN031190,NGEN031208,NGEN031219,NGEN031254,NGEN031277,NGEN031298,NGEN031303,NGEN031337,NGEN031353,NGEN031369,NGEN031399,NGEN031404,NGEN031426,NGEN031508,NGEN031640,NGEN031647,NGEN031653,NGEN031752,NGEN031759,NGEN031777,NGEN031796,NGEN031881,NGEN031927,NGEN031969,NGEN031978,NGEN032013,NGEN032023,NGEN032032,NGEN032120,NGEN032324,NGEN032340,NGEN032396,NGEN032400,NGEN032458,NGEN032528,NGEN032575,NGEN032662,NGEN032674,NGEN032686,NGEN032703,NGEN032723,NGEN032749,NGEN032787,NGEN032867,NGEN032923,NGEN032980,NGEN032987,NGEN033068,NGEN033103,NGEN033148,NGEN033210,NGEN033299,NGEN033360,NGEN033405,NGEN033463,NGEN033491,NGEN001526,NGEN033591,NGEN001655,NGEN033748,NGEN033754,NGEN033784,NGEN033805,NGEN033825,NGEN033852,NGEN033922,NGEN033923,NGEN033963,NGEN033990,NGEN034007,NGEN034021,NGEN034095,NGEN034103,NGEN034141,NGEN034145,NGEN034187,NGEN034188,NGEN034241,NGEN034257,NGEN034303,NGEN034388,NGEN034391,NGEN034414,NGEN034536,NGEN034558,NGEN034592,NGEN034645,NGEN034690,NGEN034701,NGEN034716,NGEN034724,NGEN034863,NGEN034927,NGEN034993,NGEN035012,NGEN035026,NGEN035030,NGEN035082,NGEN035111,NGEN035172,NGEN035227,NGEN035365,NGEN035396,NGEN035408,NGEN035487,NGEN035526,NGEN035532,NGEN035665,NGEN000484,NGEN000489,NGEN000561,NGEN000583,NGEN000584,NGEN000705,NGEN000734,NGEN000736,NGEN000755,NGEN000765,NGEN000792,NGEN000793,NGEN000809,NGEN000832,NGEN000848,NGEN000882,NGEN000967,NGEN001076,NGEN001148,NGEN001198,NGEN001250,NGEN001271,NGEN001288,NGEN001355,NGEN001363,NGEN001436,NGEN001452,NGEN001454,NGEN001494,NGEN001512,NGEN001563,NGEN001573,NGEN001575,NGEN001590,NGEN001603,NGEN001636,NGEN001665,NGEN001681,NGEN001709,NGEN001737,NGEN001726,NGEN001770,NGEN001790,NGEN001812,NGEN001816,NGEN001921,NGEN001977,NGEN001990,NGEN002025,NGEN002063,NGEN002070,NGEN003723,NGEN002104,NGEN002107,NGEN002111,NGEN002136,NGEN002222,NGEN002237,NGEN002308,NGEN002312,NGEN002330,NGEN002407,NGEN002426,NGEN002442,NGEN002488,NGEN002491,NGEN002500,NGEN002518,NGEN002586,NGEN002551,NGEN002561,NGEN002599,NGEN002602,NGEN002667,NGEN002675,NGEN002678,NGEN002689,NGEN002704,NGEN002707,NGEN002713,NGEN002798,NGEN002810,NGEN002831,NGEN002838,NGEN002853,NGEN002857,NGEN002872,NGEN002902,NGEN002910,NGEN002918,NGEN002927,NGEN002933,NGEN008154,NGEN003036,NGEN003054,NGEN003101,NGEN003103,NGEN003124,NGEN003135,NGEN003375,NGEN003176,NGEN003177,NGEN003194,NGEN003206,NGEN003264,NGEN003365,NGEN003362,NGEN003370,NGEN003466,NGEN003468,NGEN003502,NGEN003512,NGEN003531,NGEN003549,NGEN003572,NGEN003681,NGEN003684,NGEN003750,NGEN005141,NGEN003890,NGEN003930,NGEN003932,NGEN003943,NGEN003988,NGEN004021,NGEN004048,NGEN004067,NGEN004076,NGEN004094,NGEN004104,NGEN004130,NGEN004147,NGEN004196,NGEN004222,NGEN004227,NGEN004231,NGEN004254,NGEN005499,NGEN004288,NGEN004304,NGEN004345,NGEN004375,NGEN004398,NGEN004403,NGEN004424,NGEN004457,NGEN004509,NGEN004512,NGEN004517,NGEN004526,NGEN004630,NGEN004652,NGEN004697,NGEN004722,NGEN004747,NGEN004772,NGEN004901,NGEN004918,NGEN004999,NGEN005044,NGEN005041,NGEN005056,NGEN005063,NGEN005073,NGEN005127,NGEN005138,NGEN005153,NGEN005208,NGEN005222,NGEN005257,NGEN005260,NGEN005300,NGEN005358,NGEN005372,NGEN005500,NGEN005459,NGEN005475,NGEN005537,NGEN005563,NGEN005620,NGEN005671,NGEN005780,NGEN005714,NGEN005731,NGEN005746,NGEN005750,NGEN005799,NGEN005821,NGEN005869,NGEN005881,NGEN005896,NGEN005917,NGEN005944,NGEN005960,NGEN005990,NGEN006109,NGEN006166,NGEN006178,NGEN006219,NGEN006261,NGEN006316,NGEN006328,NGEN006389,NGEN006432,NGEN006456,NGEN006496,NGEN006531,NGEN006541,NGEN006589,NGEN006685,NGEN006716,NGEN006775,NGEN006741,NGEN006743,NGEN006786,NGEN006814,NGEN006834,NGEN006848,NGEN006858,NGEN006864,NGEN006867,NGEN006897,NGEN006989,NGEN006995,NGEN007005,NGEN007035,NGEN007048,NGEN007066,NGEN007081,NGEN007092,NGEN007096,NGEN007163,NGEN007217,NGEN007263,NGEN007314,NGEN007323,NGEN007345,NGEN007359,NGEN007360,NGEN007466,NGEN007478,NGEN007514,NGEN007548,NGEN007563,NGEN007630,NGEN007638,NGEN007661,NGEN007672,NGEN007714,NGEN007674,NGEN007788,NGEN007826,NGEN007846,NGEN007867,NGEN007870,NGEN007871,NGEN007872,NGEN008044,NGEN008184,NGEN008254,NGEN008297,NGEN008355,NGEN008393,NGEN008414,NGEN008443,NGEN008458,NGEN008791,NGEN008523,NGEN008551,NGEN008586,NGEN008628,NGEN008647,NGEN008714,NGEN008726,NGEN008736,NGEN008813,NGEN008817,NGEN008882,NGEN008908,NGEN008938,NGEN009082,NGEN009156,NGEN009186,NGEN009290,NGEN009294,NGEN009330,NGEN009377,NGEN009391,NGEN009413,NGEN009422,NGEN009440,NGEN009459,NGEN009482,NGEN009515,NGEN009527,NGEN009535,NGEN009541,NGEN009793,NGEN009636,NGEN009751,NGEN009799,NGEN009855,NGEN009881,NGEN009884,NGEN009903,NGEN010077,NGEN010035,NGEN010079,NGEN010096,NGEN010123,NGEN010155,NGEN010243,NGEN010249,NGEN010297,NGEN010308,NGEN010363,NGEN010490,NGEN010422,NGEN010461,NGEN010519,NGEN010531,NGEN010572,NGEN010583,NGEN010655,NGEN010661,NGEN010692,NGEN010699,NGEN010720,NGEN010724,NGEN010730,NGEN010778,NGEN010803,NGEN010855,NGEN010834,NGEN010850,NGEN010851,NGEN010858,NGEN010880,NGEN010896,NGEN010983,NGEN011036,NGEN011046,NGEN011069,NGEN011126,NGEN011146,NGEN011299,NGEN011224,NGEN011243,NGEN011412,NGEN011413,NGEN011529,NGEN011560,NGEN011563,NGEN011573,NGEN011619,NGEN011664,NGEN011678,NGEN011700,NGEN011719,NGEN011769,NGEN011796,NGEN011828,NGEN011831,NGEN011861,NGEN011970,NGEN011993,NGEN012033,NGEN012055,NGEN012101,NGEN012117,NGEN012172,NGEN012198,NGEN012240,NGEN012243,NGEN012300,NGEN012343,NGEN012359,NGEN012415,NGEN012426,NGEN012437,NGEN012487,NGEN012489,NGEN012498,NGEN012547,NGEN012586,NGEN012594,NGEN012697,NGEN012713,NGEN012924,NGEN012995,NGEN013133,NGEN013186,NGEN013253,NGEN013301,NGEN013305,NGEN013328,NGEN013353,NGEN013363,NGEN013372,NGEN013378,NGEN013400,NGEN013444,NGEN013452,NGEN013492,NGEN013495,NGEN013514,NGEN013527,NGEN013570,NGEN013602,NGEN013610,NGEN014051,NGEN013626,NGEN013654,NGEN013698,NGEN013713,NGEN013770,NGEN013786,NGEN013822,NGEN013831,NGEN013855,NGEN013893,NGEN013962,NGEN014054,NGEN014101,NGEN014112,NGEN014142,NGEN014231,NGEN014270,NGEN014309,NGEN014324,NGEN014345,NGEN014420,NGEN014426,NGEN014468,NGEN014491,NGEN014519,NGEN014552,NGEN014579,NGEN014979,NGEN014615,NGEN014672,NGEN014729,NGEN014839,NGEN014925,NGEN014955,NGEN015067,NGEN015151,NGEN015156,NGEN015162,NGEN015165,NGEN015182,NGEN015187,NGEN015226,NGEN015248,NGEN015276,NGEN015284,NGEN015301,NGEN015327,NGEN015353,NGEN015365,NGEN015434,NGEN015458,NGEN015501,NGEN015579,NGEN015580,NGEN015589,NGEN015664,NGEN015672,NGEN015694,NGEN015749,NGEN015753,NGEN015769,NGEN015821,NGEN024717,NGEN024952,NGEN025431,NGEN025467,NGEN025516,NGEN026010,NGEN026040,NGEN026268,NGEN026457,NGEN026546,NGEN026563,NGEN026575,NGEN026732,NGEN026789,NGEN026819,NGEN026896,NGEN027067,NGEN027160,NGEN027749,NGEN028102,NGEN028505,NGEN028935,NGEN029177,NGEN029383,NGEN029444,NGEN029746,NGEN029927,NGEN030360,NGEN031325,NGEN031390,NGEN031471,NGEN032171,NGEN032274,NGEN032437,NGEN032862,NGEN033141,NGEN033676,NGEN033997,NGEN034174,NGEN034378,NGEN034385,NGEN034397,NGEN034524,NGEN034721,NGEN035294,NGEN035328,NGGT000242,NGGT000235,NGGT000236,NGGT000237,NGGT000238,NGGT000239,NGGT000240,NGGT000241,NGGT000243,NGGT000244,NGGT000245,NGGT000246,NGGT000247,NGGT000284,NGGT000285,NGGT000286,NGGT000287,NGGT000288,NGGT000289,NGGT000290,NGGT000291,NGGT000292,NGGT000293,NGGT000294,NGGT000295,NGGT000296,NGGT000333,NGGT000334,NGGT000335,NGGT000336,NGGT000337,NGGT000338,NGGT000339,NGGT000340,NGGT000341,NGGT000342,NGGT000343,NGGT000344,NGGT000345,NGGT000382,NGGT000383,NGGT000384,NGGT000385,NGGT000386,NGGT000387,NGGT000388,NGGT000389,NGGT000390,NGGT000391,NGGT000392,NGGT000393,NGGT000394 --commit --verbose > $LOG_FILE_DIR/FILER/load_gene_brain_overlaps_chr19.log 2>&1