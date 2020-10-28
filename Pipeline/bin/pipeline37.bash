# CREATE CBIL/NIAGADS SCHEMAS
# CREATE FUNCTIONS


# DEPENDENCIES
# =============================

# Sequence Ontology

loadResource --config $CONFIG_DIR/ontologies/sequence_ontology.json --load xdbr --commit > $DATA_DIR/logs/load_sequence_ontology_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/sequence_ontology.json --load data --commit > $DATA_DIR/logs/load_sequence_ontology.log 2>&1

# Taxon

ga GUS::Supported::Plugin::LoadGusXml --filename $GUS_HOME/lib/xml/sres/taxon.xml --comment "ga GUS::Supported::Plugin::LoadGusXml --filename $GUS_HOME/lib/xml/sres/taxon.xml" --commit > $DATA_DIR/logs/load_taxon.log 2>&1


# Genome
# =============================

# Genome

loadResource --config $CONFIG_DIR/reference_databases/hg19_genome.json --load xdbr --commit > $DATA_DIR/logs/load_hg19_genome_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/hg19_genome.json --load data --commit > $DATA_DIR/logs/load_hg19_genome.log 2>&1

# Create bin Index Reference

# ga CBILDataCommon::Load::Plugin::InsertBinIndexRef --comment "ga CBILDataCommon::Load::Plugin::InsertBinIndexRef" --commit > $DATA_DIR/logs/load_bin_index_reference.log 2>&1


# Gene Reference
# =============================

# Genes

loadResource --config $CONFIG_DIR/reference_databases/hg19_genes.json --load xdbr --commit > $DATA_DIR/logs/load_hg19_genes_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/hg19_genes.json --preprocess --verbose > $DATA_DIR/logs/load_hg19_genes_preprocess.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/hg19_genes.json --load data --commit  > $DATA_DIR/logs/load_hg19_genes.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/hg10_genes.json --tuning --verbose --commit  > $DATA_DIR/logs/load_transcript_tuning.log 2>&1

# HGNC

loadResource --config $CONFIG_DIR/reference_databases/hgnc.json --load xdbr --commit > $DATA_DIR/logs/load_hgnc_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/hgnc.json --preprocess --verbose > $DATA_DIR/logs/load_hgnc_preprocess.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/hgnc.json --load data --verbose --commit  > $DATA_DIR/logs/load_hgnc.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/hgnc.json --tuning --verbose --commit  > $DATA_DIR/logs/load_hgnc_tuning.log 2>&1

# GO

loadResource --config $CONFIG_DIR/ontologies/gene_ontology.json --load xdbr --commit --verbose > $DATA_DIR/logs/load_gene_ontology_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/gene_ontology.json --load data --commit --verbose > $DATA_DIR/logs/load_gene_ontology.log 2>&1


# Gene-GO Association

loadResource --config $CONFIG_DIR/reference_databases/go_references.json --load xdbr --commit --verbose > $DATA_DIR/logs/load_go_references_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/go_references.json --load data --commit --verbose > $DATA_DIR/logs/load_go_references.log 2>&1

loadResource --config $CONFIG_DIR/reference_databases/uniprot_entity_map.json --load xdbr --commit --verbose > $DATA_DIR/logs/load_uniprot_entity_map_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/go_gene_annotation.json --load xdbr --commit --verbose > $DATA_DIR/logs/load_go_gene_association_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/go_gene_annotation.json --load data --commit --verbose > $DATA_DIR/logs/load_go_gene_association.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/go_gene_annotation.json --tuning --verbose > $DATA_DIR/logs/load_go_gene_association_tuning.log 2>&1

# KEGG
loadResource --config $CONFIG_DIR/reference_databases/kegg.json --load xdbr --verbose --commit > $DATA_DIR/logs/load_kegg_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/kegg.json --preprocess --verbose > $DATA_DIR/logs/preprocess_kegg.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/kegg.json --load data --verbose --commit > $DATA_DIR/logs/load_kegg.log 2>&1 

# REACTOME
loadResource --config $CONFIG_DIR/reference_databases/reactome.json --load xdbr --verbose --commit > $DATA_DIR/logs/load_reactome_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/reactome.json --load data --verbose --commit > $DATA_DIR/logs/load_reactome.log 2>&1 

loadResource --config $CONFIG_DIR/reference_databases/reactome_tc.json --load xdbr --verbose --commit > $DATA_DIR/logs/load_reactome_tc_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/reactome_tc.json --load data --verbose --commit > $DATA_DIR/logs/load_reactome_tc.log 2>&1 



# Ontologies
# =============================

# Niagads Ontology

loadResource --config $CONFIG_DIR/ontologies/niagads_ontology.json --load xdbr --commit --verbose > $DATA_DIR/logs/load_niagads_ontology_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/niagads_ontology.json --preprocess --verbose > $DATA_DIR/logs/load_niagads_ontology_preprocess.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/niagads_ontology.json --load data --commit --verbose > $DATA_DIR/logs/load_niagads_ontology.log 2>&1

# CHEBI 

loadResource --config $CONFIG_DIR/ontologies/chebi.json --load xdbr --commit --verbose > $DATA_DIR/logs/load_chebi_xdbr.log 2>&1
# loadResource --config $CONFIG_DIR/ontologies/chebi.json --load data --commit --verbose > $DATA_DIR/logs/load_chebi.log 2>&1

# PRO

loadResource --config $CONFIG_DIR/ontologies/pro.json --load xdbr --commit --verbose > $DATA_DIR/logs/load_pro_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/pro.json --load data --commit --verbose > $DATA_DIR/logs/load_pro.log 2>&1

# EDAM

loadResource --config $CONFIG_DIR/ontologies/edam.json --load xdbr --commit --verbose > $DATA_DIR/logs/load_edam_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/edam.json --load data --commit --verbose > $DATA_DIR/logs/load_edam.log 2>&1

# EFO

loadResource --config $CONFIG_DIR/ontologies/efo.json --load xdbr --commit --verbose > $DATA_DIR/logs/load_efo_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/efo.json --load data --commit --verbose > $DATA_DIR/logs/load_efo.log 2>&1

# UBERON

loadResource --config $CONFIG_DIR/ontologies/uberon.json --load xdbr --commit --verbose > $DATA_DIR/logs/load_uberon_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/uberon.json --load data --commit --verbose > $DATA_DIR/logs/load_uberon.log 2>&1

# STATO

loadResource --config $CONFIG_DIR/ontologies/stato.json --load xdbr --commit --verbose > $DATA_DIR/logs/load_stato_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/stato.json --load data --commit --verbose > $DATA_DIR/logs/load_stato.log 2>&1

# ECO

loadResource --config $CONFIG_DIR/ontologies/eco.json --load xdbr --commit --verbose > $DATA_DIR/logs/load_eco_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/eco.json --load data --commit --verbose > $DATA_DIR/logs/load_eco.log 2>&1

# cell

loadResource --config $CONFIG_DIR/ontologies/cell.json --load xdbr --commit --verbose > $DATA_DIR/logs/load_cell_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/cell.json --load data --commit --verbose > $DATA_DIR/logs/load_cell.log 2>&1




# Variants
# =============================


# DBSNP -- now in annotatedvdb



# 1000Genomes/LD

loadResource -c $CONFIG_DIR/analyses/ld.json --load xdbr --commit > $DATA_DIR/logs/load_ld_xdbr.log 2>&1
loadResource -c $CONFIG_DIR/analyses/ld.json --preprocess --verbose > $DATA_DIR/logs/load_ld_preprocess.log 2>&1
loadResource -c $CONFIG_DIR/analyses/ld.json --load data --verbose --commit > $DATA_DIR/logs/load_ld.log 2>&1


# ADSP

loadResource --config $CONFIG_DIR/adsp/wes_qc_19.json --load xdbr --commit > $DATA_DIR/logs/load_adsp_wes_xdbr.log 2>&1
gunzip $DATA_DIR/ADSP/QC/WES/*.gz
# loadResource --config $CONFIG_DIR/adsp/wes_qc_19.json --preprocess --verbose > $DATA_DIR/logs/preprocess_adsp_wes.log 2>&1
loadResource --config $CONFIG_DIR/adsp/wes_qc_19.json --load data  --params '{"loadVariants":"true", "bulkLoad":"true","commitAfter":"30000"}' --verbose --commit > $DATA_DIR/ADSP/QC/WES/load_adsp_wes.log 2>&1
loadResource --config $CONFIG_DIR/adsp/wes_qc_19.json --load data  --params '{"annotateNovelVariants":"true"}' --verbose --commit > $DATA_DIR/ADSP/QC/WES/annotate_adsp_wes_novel.log 2>&1
loadResource --config $CONFIG_DIR/adsp/wes_qc_19.json --load data  --params '{"loadNovelVariants":"true", "bulkLoad":"true","commitAfter":"5000"}' --verbose --commit > $DATA_DIR/ADSP/QC/WES/load_adsp_wes_novel.log 2>&1
gzip $DATA_DIR/ADSP/QC/WES/*.txt

loadResource --config $CONFIG_DIR/adsp/wgs_qc_19.json --load xdbr --commit > $DATA_DIR/logs/load_adsp_wgs_xdbr.log 2>&1
gunzip $DATA_DIR/ADSP/QC/WGS/*.gz
# loadResource --config $CONFIG_DIR/adsp/wgs_qc_19.json --preprocess --verbose > $DATA_DIR/logs/preprocess_adsp_wgs.log 2>&1
loadResource --config $CONFIG_DIR/adsp/wgs_qc_19.json --load data  --params '{"loadVariants":"true", "bulkLoad":"true","commitAfter":"30000"}' --verbose --commit > $DATA_DIR/ADSP/QC/WGS/load_adsp_wgs.log 2>&1
loadResource --config $CONFIG_DIR/adsp/wgs_qc_19.json --load data  --params '{"annotateNovelVariants":"true"}' --verbose --commit > $DATA_DIR/ADSP/QC/WGS/annotate_adsp_wgs_novel.log 2>&1
loadResource --config $CONFIG_DIR/adsp/wgs_qc_19.json --load data  --params '{"loadNovelVariants":"true", "bulkLoad":"true","commitAfter":"5000"}' --verbose --commit > $DATA_DIR/ADSP/QC/WGS/load_adsp_wgs_novel.log 2>&1
gzip $DATA_DIR/ADSP/QC/WGS/*.txt


loadResource --config $CONFIG_DIR/adsp/wes_indels_19.json --load xdbr --commit > $DATA_DIR/logs/load_adsp_wes_indels_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/adsp/wes_indels_19.json --preprocess --verbose > $DATA_DIR/logs/preprocess_adsp_wes_indels.log 2>&1
loadResource --config $CONFIG_DIR/adsp/wes_indesl_19.json --load data --params '{"loadVariants":"true"}' --commit  --verbose > $DATA_DIR/logs/load_adsp_wes_indels.log 2>&1
loadResource --config $CONFIG_DIR/adsp/wes_indesl_19.json --load data --params '{"annotateNovelVariants":"true"}' --commit  --verbose > $DATA_DIR/logs/load_adsp_wes_indels.log 2>&1
loadResource --config $CONFIG_DIR/adsp/wes_indesl_19.json --load data --params '{"loadNovelVariants":"true"}' --commit  --verbose > $DATA_DIR/logs/load_adsp_wes_indels.log 2>&1



# VEP/CADD -- now in Annotated VDB
# allele frequencies -- now in AnnotatedVDB

# ExAC

loadResource -c $CONFIG_DIR/annotations/exac_freq.json  --load xdbr --verbose --commit > $DATA_DIR/logs/load_exac_xdbr.log 2>&1
loadResource -c $CONFIG_DIR/annotations/exac_freq.json  --preprocess --verbose  > $DATA_DIR/logs/preproces_exac.log 2>&1
loadResource -c $CONFIG_DIR/annotations/exac_freq.json  --load data --verbose --commit > $DATA_DIR/logs/load_exac.log 2>&1


# GWAS
# =============================


# NHGRI GWAS Catalog

loadResource -c $CONFIG_DIR/reference_databases/gwas_catalog.json --load xdbr --verbose --commit > $DATA_DIR/logs/load_nhgri_gc_xdbr.log 2>&1
loadResource -c $CONFIG_DIR/reference_databases/gwas_catalog.json --preprocess --verbose > $DATA_DIR/logs/preprocess_nhgri_gc.log 2>&1
loadResource -c $CONFIG_DIR/reference_databases/gwas_catalog.json --load --commit --verbose > $DATA_DIR/logs/load_nhgri_gc.log 2>&1




# NG00027
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00027.json --load xdbr --verbose --commit > $DATA_DIR/logs/datasets/load_NIAGADS_DATASET_xdbr.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00027.json --load data  --commit > $DATA_DIR/logs/datasets/load_NG00027_placeholders.log 2>&1 # comment out LoadVariantGwAS for this step/comment out InsertStudy & InsertProtocolAppNodes for next
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00027.json --load data --params '{"findNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00027_find_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00027.json --load data --params '{"annotateNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00027_annotate_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00027.json --load data --params '{"preprocessAnnotatedNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00027_preprocess_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00027.json --load data --params '{"loadVariants":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00027_load_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00027.json --load data --params '{"loadResult":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00027_load_result.log 2>&1


# NG00036
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00036.json --load data  --commit > $DATA_DIR/logs/datasets/load_NG00036_placeholders.log 2>&1 # comment out LoadVariantGwAS for this step/comment out InsertStudy & InsertProtocolAppNodes for next
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00036.json --load data --params '{"findNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00036_find_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00036.json --load data --params '{"annotateNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00036_annotate_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00036.json --load data --params '{"preprocessAnnotatedNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00036_preprocess_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00036.json --load data --params '{"loadVariants":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00036_load_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00036.json --load data --params '{"loadResult":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00036_load_result.log 2>&1


# NG00039
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00039.json --load data  --commit > $DATA_DIR/logs/datasets/load_NG00039_placeholders.log 2>&1 # comment out LoadVariantGwAS for this step/comment out InsertStudy & InsertProtocolAppNodes for next
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00039.json --load data --params '{"findNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00039_find_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00039.json --load data --params '{"annotateNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00039_annotate_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00039.json --load data --params '{"preprocessAnnotatedNovelVariants":"true","skipMetaseqIdValidation":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00039_preprocess_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00039.json --load data --params '{"loadVariants":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00039_load_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00039.json --load data --params '{"loadResult":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00039_load_result.log 2>&1

# NG00040 -- TODO
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00040.json --preprocess --commit --verbose > $DATA_DIR/logs/preprocess_NG00040.log 2>&1

# NG00041

loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00041.json --load data  --commit > $DATA_DIR/logs/datasets/load_NG00041_placeholders.log 2>&1 # comment out LoadVariantGwAS for this step/comment out InsertStudy & InsertProtocolAppNodes for next
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00041.json --load data --params '{"findNovelVariants":"true"}' --verbose --foreach LEWY,NP_CONS,CAA,LEWY_5 > $DATA_DIR/logs/datasets/load_NG00041_find_novel_variants1.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00041.json --load data --params '{"findNovelVariants":"true"}' --verbose --foreach NP_RELAX,NFT_BGROUPS,HS  > $DATA_DIR/logs/datasets/load_NG00041_find_novel_variants2.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00041.json --load data --params '{"findNovelVariants":"true"}' --verbose --foreach NFT_BSTAGES,NP,VBI,LEWY_3 > $DATA_DIR/logs/datasets/load_NG00041_find_novel_variants3.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00041.json --load data --params '{"findNovelVariants":"true"}' --verbose --foreach NP_CERAD,VBI_3,STATUS > $DATA_DIR/logs/datasets/load_NG00041_find_novel_variants4.log 2>&1


loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00041.json --load data --params '{"annotateNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00041_annotate_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00041.json --load data --params '{"preprocessAnnotatedNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00041_preprocess_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00041.json --load data --params '{"loadVariants":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00041_load_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00041.json --load data --params '{"loadResult":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00041_load_result.log 2>&1

# NG00045

loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00045.json --load data  --commit > $DATA_DIR/logs/datasets/load_NG00045_placeholders.log 2>&1 # comment out LoadVariantGwAS for this step/comment out InsertStudy & InsertProtocolAppNodes for next
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00045.json --load data --params '{"findNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00045_find_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00045.json --load data --params '{"annotateNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00045_annotate_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00045.json --load data --params '{"preprocessAnnotatedNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00045_preprocess_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00045.json --load data --params '{"loadVariants":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00045_load_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00045.json --load data --params '{"loadResult":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00045_load_result.log 2>&1


# NG00048
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00048.json --load data  --commit > $DATA_DIR/logs/datasets/load_NG00048_placeholders.log 2>&1 # comment out LoadVariantGwAS for this step/comment out InsertStudy & InsertProtocolAppNodes for next
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00048.json --load data --params '{"findNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00048_find_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00048.json --load data --params '{"annotateNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00048_annotate_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00048.json --load data --params '{"preprocessAnnotatedNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00048_preprocess_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00048.json --load data --params '{"loadVariants":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00048_load_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00048.json --load data --params '{"loadResult":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00048_load_result.log 2>&1


# NG00049
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00049.json --load data  --commit > $DATA_DIR/logs/datasets/load_NG00049_placeholders.log 2>&1 # comment out LoadVariantGwAS for this step/comment out InsertStudy & InsertProtocolAppNodes for next
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00049.json --load data --params '{"findNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00049_find_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00049.json --load data --params '{"annotateNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00049_annotate_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00049.json --load data --params '{"preprocessAnnotatedNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00049_preprocess_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00049.json --load data --params '{"loadVariants":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00049_load_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00049.json --load data --params '{"loadResult":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00049_load_result.log 2>&1


# NG00052

loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00052.json --load data  --commit > $DATA_DIR/logs/datasets/load_NG00052_placeholders.log 2>&1 # comment out LoadVariantGwAS for this step/comment out InsertStudy & InsertProtocolAppNodes for next
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00052.json --load data --params '{"findNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00052_find_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00052.json --load data --params '{"annotateNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00052_annotate_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00052.json --load data --params '{"preprocessAnnotatedNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00052_preprocess_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00052.json --load data --params '{"loadVariants":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00052_load_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00052.json --load data --params '{"loadResult":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00052_load_result.log 2>&1

# NG00053

loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00053.json --load data  --commit > $DATA_DIR/logs/datasets/load_NG00053_placeholders.log 2>&1 # comment out LoadVariantGwAS for this step/comment out InsertStudy & InsertProtocolAppNodes for next
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00053.json --load data --params '{"findNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00053_find_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00053.json --load data --params '{"annotateNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00053_annotate_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00053.json --load data --params '{"preprocessAnnotatedNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00053_preprocess_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00053.json --load data --params '{"loadVariants":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00053_load_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00053.json --load data --params '{"loadResult":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00053_load_result.log 2>&1

# NG00055

loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00055.json --load data  --commit > $DATA_DIR/logs/datasets/load_NG00055_placeholders.log 2>&1 # comment out LoadVariantGwAS for this step/comment out InsertStudy & InsertProtocolAppNodes for next
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00055.json --load data --params '{"findNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00055_find_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00055.json --load data --params '{"annotateNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00055_annotate_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00055.json --load data --params '{"preprocessAnnotatedNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00055_preprocess_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00055.json --load data --params '{"loadVariants":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00055_load_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00055.json --load data --params '{"loadResult":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00055_load_result.log 2>&1

# NG00056

loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00056.json --load data  --commit > $DATA_DIR/logs/datasets/load_NG00056_placeholders.log 2>&1 # comment out LoadVariantGwAS for this step/comment out InsertStudy & InsertProtocolAppNodes for next
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00056.json --load data --params '{"findNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00056_find_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00056.json --load data --params '{"annotateNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00056_annotate_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00056.json --load data --params '{"preprocessAnnotatedNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00056_preprocess_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00056.json --load data --params '{"loadVariants":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00056_load_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00056.json --load data --params '{"loadResult":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00056_load_result.log 2>&1

# NG00058

loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00058.json --load data  --commit > $DATA_DIR/logs/datasets/load_NG00058_placeholders.log 2>&1 # comment out LoadVariantGwAS for this step/comment out InsertStudy & InsertProtocolAppNodes for next
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00058.json --load data --params '{"findNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00058_find_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00058.json --load data --params '{"annotateNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00058_annotate_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00058.json --load data --params '{"preprocessAnnotatedNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00058_preprocess_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00058.json --load data --params '{"loadVariants":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00058_load_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00058.json --load data --params '{"loadResult":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00058_load_result.log 2>&1

# NG00073

loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00073.json --load data  --commit > $DATA_DIR/logs/datasets/load_NG00073_placeholders.log 2>&1 # comment out LoadVariantGwAS for this step/comment out InsertStudy & InsertProtocolAppNodes for next
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00073.json --load data --params '{"findNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00073_find_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00073.json --load data --params '{"annotateNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00073_annotate_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00073.json --load data --params '{"preprocessAnnotatedNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00073_preprocess_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00073.json --load data --params '{"loadVariants":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00073_load_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00073.json --load data --params '{"loadResult":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00073_load_result.log 2>&1

# NG00074 -- TODO

# NG00075

loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00075.json --load data  --commit > $DATA_DIR/logs/datasets/load_NG00075_placeholders.log 2>&1 # comment out LoadVariantGwAS for this step/comment out InsertStudy & InsertProtocolAppNodes for next
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00075.json --load data --params '{"findNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00075_find_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00075.json --load data --params '{"annotateNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00075_annotate_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00075.json --load data --params '{"preprocessAnnotatedNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00075_preprocess_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00075.json --load data --params '{"loadVariants":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00075_load_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00075.json --load data --params '{"loadResult":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00075_load_result.log 2>&1


# NG00076

loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00076.json --load data  --commit > $DATA_DIR/logs/datasets/load_NG00076_placeholders.log 2>&1 # comment out LoadVariantGwAS for this step/comment out InsertStudy & InsertProtocolAppNodes for next
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00076.json --load data --params '{"findNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00076_find_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00076.json --load data --params '{"annotateNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00076_annotate_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00076.json --load data --params '{"preprocessAnnotatedNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00076_preprocess_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00076.json --load data --params '{"loadVariants":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00076_load_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00076.json --load data --params '{"loadResult":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00076_load_result.log 2>&1

# NG00078

loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00078.json --load data  --commit > $DATA_DIR/logs/datasets/load_NG00078_placeholders.log 2>&1 # comment out LoadVariantGwAS for this step/comment out InsertStudy & InsertProtocolAppNodes for next
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00078.json --load data --params '{"findNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00078_find_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00078.json --load data --params '{"annotateNovelVariants":"true"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00078_annotate_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00078.json --load data --params '{"preprocessAnnotatedNovelVariants":"true"}' --verbose  > $DATA_DIR/logs/datasets/load_NG00078_preprocess_novel_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00078.json --load data --params '{"loadVariants":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00078_load_variants.log 2>&1
loadResource -c /home/allenem/gus4_genomics/project_home/NiagadsData/Pipeline/config/datasets/NG00078.json --load data --params '{"loadResult":"true", "commitAfter":"50000"}' --verbose --commit > $DATA_DIR/logs/datasets/load_NG00078_load_result.log 2>&1




## HERE







# Functional Genomics
# ============================
loadResource -c $CONFIG_DIR/annotations/fantom5.json --load xdbr --commit > $DATA_DIR/logs/load_fantom5_xdbr.log 2>&1
loadResource -c $CONFIG_DIR/annotations/fantom5.json --preprocess --verbose --commit > $DATA_DIR/logs/load_fantom5_study.log 2>&1
loadResource -c $CONFIG_DIR/annotations/fantom5.json --load data --verbose --commit > $DATA_DIR/logs/load_fantom5.log 2>&1

loadResource -c $CONFIG_DIR/annotations/roadmap_enhancers.json --load xdbr --commit > $DATA_DIR/logs/load_roadmap_enhancers_xdbr.log 2>&1
loadResource -c $CONFIG_DIR/annotations/roadmap_enhancers.json --preprocess  --commit > $DATA_DIR/logs/load_roadmap_enhancers_study.log 2>&1
loadResource -c $CONFIG_DIR/annotations/roadmap_enhancers.json --load data --verbose --commit > $DATA_DIR/logs/load_roadmap_enhancers.log 2>&1


