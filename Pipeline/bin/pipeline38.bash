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
loadResource --config $CONFIG_DIR/adsp/17K_annotation.json --load data --verbose --commit > $DATA_DIR/logs/data/load_adsp_17K_vep.log 2>&1 # skip cadd
loadResource --config $CONFIG_DIR/adsp/17K_annotation.json --load data --verbose --commit > $DATA_DIR/logs/data/load_adsp_17K_cadd.log 2>&1 # skip vep

# QC

# =================================================
# EBI-EMBL GWAS Catalog
# =================================================


# =================================================
# Summary Statistics
# =================================================

# external db before first load
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json --load xdbr --verbose --commit > $DATA_DIR/logs/xdbr/load_NIAGADS_DATASET_xdbr.log 2>&1
# should be the same in all the config files for NIAGADS accessions, so don't need to run again


# NG00027

mkdir $DATA_DIR/logs/datasets/NG00027
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00027/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00027/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00027/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00027/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00027/update_GRCh37.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00027/update_GRCh38.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00027/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00027/GRCh38_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json  --load data --params '{"genomeBuild":"GRCh37", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00027/GRCH37_archive.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00027.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00027/GRCh38_archive.log 2>&1

# NG00036

mkdir $DATA_DIR/logs/datasets/NG00036
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00036.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00036/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00036.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00036/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00036.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00036/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00036.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00036/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00036.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00036/update_GRCh37.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00036.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00036/update_GRCh38.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00036.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose  > $DATA_DIR/logs/datasets/NG00036/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00036.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose  > $DATA_DIR/logs/datasets/NG00036/GRCh38_standardize.log 2>&1


# NG00039

mkdir $DATA_DIR/logs/datasets/NG00039
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00039.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00039/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00039.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00039/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00039.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00039/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00039.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00039/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00039.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00039/update_GRCh37.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00039.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00039/update_GRCh38.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00039.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00039/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00039.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00039/GRCh38_standardize.log 2>&1

# NG00040

mkdir $DATA_DIR/logs/datasets/NG00040
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00040.json --verbose  --preprocess  --commit > $DATA_DIR/logs/datasets/NG00040/placeholders.log 2>&1 
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00040.json --load data --params '{"liftOver":"true", "genomeBuild":"GRCh37"}' --verbose > $DATA_DIR/logs/datasets/NG00040/lift_over.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00040.json --load data --params '{"preprocess":"true", "genomeBuild":"GRCh38"}' --commit --verbose > $DATA_DIR/logs/datasets/NG00040/preprocess.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00040.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00040/load_result.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00040.json --load data --params '{"liftOver":"true", "updateFlags":"true", "genomeBuild":"GRCh37", "updateGusConfig":"$GUS_HOME/config/grch37-annotatedvdb-gus.config"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00040/update_GRCh37.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00040.json --load data --params '{"updateFlags":"true", "genomeBuild":"GRCh38"}' --verbose --commit > $DATA_DIR/logs/datasets/NG00040/update_GRCh38.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00040.json  --load data --params '{"genomeBuild":"GRCh37", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00040/GRCh37_standardize.log 2>&1
loadResource -c $PROJECT_HOME/GenomicsDBData/Pipeline/config/datasets/NG00040.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $DATA_DIR/logs/datasets/NG00040/GRCh38_standardize.log 2>&1
