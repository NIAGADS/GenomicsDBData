
# =================================================
# ADSP R4/36K
# =================================================

# variants

loadResource --config $CONFIG_DIR/adsp/R4_annotation.json --load xdbr --verbose --commit > $LOG_FILE_DIR/xdbr/load_adsp_R4_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/adsp/R4_annotation.json --load data --verbose --commit > $LOG_FILE_DIR/data/load_adsp_R4_vep.log 2>&1 # skip cadd & qc

# loadResource --config $CONFIG_DIR/adsp/R4_annotation.json --load data --params '{"chr":"8,9"}' --verbose --commit > $LOG_FILE_DIR/data/load_adsp_R4_vep_8_9.log 2>&1 # skip cadd & qc

loadResource --config $CONFIG_DIR/adsp/R4_annotation.json --load data --verbose --commit > $LOG_FILE_DIR/data/load_adsp_R4_cadd.log 2>&1 # skip vep & qc
loadResource --config $CONFIG_DIR/adsp/R4_annotation.json --load data --verbose --commit > $LOG_FILE_DIR/data/load_adsp_R4_qc.log 2>&1 # skip vep & cadd


ga GUS::Supported::Plugin::LoadGusXml --file $GUS_HOME/lib/xml/niagads/r4_36k_track_config.xml --commit


# =================================================
# Datasets
# =================================================

# NG00122

mkdir $LOG_FILE_DIR/datasets/NG00122
loadResource -c $CONFIG_DIR/datasets/NG00122.json --verbose  --preprocess  --stepName GenomicsDBData::Load::Plugin::InsertStudy,GenomicsDBData::Load::Plugin::InsertProtocolAppNode --commit > $LOG_FILE_DIR/datasets/NG00122/placeholders.log 2>&1 
loadResource -c $CONFIG_DIR/datasets/NG00122.json --preprocess --stepName GenomicsDBData::GWAS::Plugin::LoadVariantGWASResult > $LOG_FILE_DIR/datasets/NG00122/preprocess_input.log 2>&1
loadResource -c $CONFIG_DIR/datasets/NG00122.json --preprocess --stepName db_map_variants.py > $LOG_FILE_DIR/datasets/NG00122/preprocess_db_map_variants.log 2>&1
loadResource -c $CONFIG_DIR/datasets/NG00122.json --preprocess --commit --stepName load_vcf_file.py > $LOG_FILE_DIR/datasets/NG00122/preprocess_load_vcf_file.log 2>&1
loadResource -c $CONFIG_DIR/datasets/NG00122.json --preprocess --stepName file_map_variants.py > $LOG_FILE_DIR/datasets/NG00122/preprocess_file_map_variants.log 2>&1

# load the data
loadResource -c $CONFIG_DIR/datasets/NG00122.json --load data --commit > $LOG_FILE_DIR/datasets/NG00122/load_result.log 2>&1

# annotate newly added variants
loadResource -c $CONFIG_DIR/datasets/NG00122.json --preprocess --stepName runVep > $LOG_FILE_DIR/datasets/NG00122/preprocess_runVep.log 2>&1
loadResource -c $CONFIG_DIR/datasets/NG00122.json --preprocess --stepName load_vep_result.py > $LOG_FILE_DIR/datasets/NG00122/preprocess_load_vep_result.log 2>&1
loadResource -c $CONFIG_DIR/datasets/NG00122.json --preprocess --stepName load_cadd_scores.py > $LOG_FILE_DIR/datasets/NG00122/preprocess_load_cadd_scores.log 2>&1
# for this load: snpEff and FAVOR will be run against entire database

