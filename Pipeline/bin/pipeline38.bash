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
loadResource -c $CONFIG_DIR/reference_databases/gwas_catalog.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/reference/preprocess_nhgri_gc.log 2>&1

loadResource -c $CONFIG_DIR/reference_databases/gwas_catalog.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/reference/load_nhgri_gc.log 2>&1



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

# NG00045 -- SKIP? TBD

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
