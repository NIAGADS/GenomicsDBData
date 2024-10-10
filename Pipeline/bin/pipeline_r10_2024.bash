
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
# NOTE: for this load: snpEff and FAVOR will be run against entire database
# =================================================

# NG00122
# -------------------------------------

mkdir $LOG_FILE_DIR/datasets/NG00122
loadResource -c $CONFIG_DIR/datasets/NG00122.json --verbose  --preprocess  --stepName GenomicsDBData::Load::Plugin::InsertStudy,GenomicsDBData::Load::Plugin::InsertProtocolAppNode --commit > $LOG_FILE_DIR/datasets/NG00122/placeholders.log 2>&1 
loadResource -c $CONFIG_DIR/datasets/NG00122.json --preprocess --stepName GenomicsDBData::GWAS::Plugin::LoadVariantGWASResult > $LOG_FILE_DIR/datasets/NG00122/preprocess_input.log 2>&1
loadResource -c $CONFIG_DIR/datasets/NG00122.json --preprocess --stepName db_map_variants.py > $LOG_FILE_DIR/datasets/NG00122/preprocess_db_map_variants.log 2>&1
loadResource -c $CONFIG_DIR/datasets/NG00122.json --preprocess --commit --stepName load_vcf_file.py > $LOG_FILE_DIR/datasets/NG00122/preprocess_load_vcf_file.log 2>&1
loadResource -c $CONFIG_DIR/datasets/NG00122.json --preprocess --stepName file_map_variants.py > $LOG_FILE_DIR/datasets/NG00122/preprocess_file_map_variants.log 2>&1

# annotate newly added variants
loadResource -c $CONFIG_DIR/datasets/NG00122.json --preprocess --stepName runVep > $LOG_FILE_DIR/datasets/NG00122/preprocess_runVep.log 2>&1
loadResource -c $CONFIG_DIR/datasets/NG00122.json --preprocess --stepName load_vep_result.py --commit > $LOG_FILE_DIR/datasets/NG00122/preprocess_load_vep_result.log 2>&1
loadResource -c $CONFIG_DIR/datasets/NG00122.json --preprocess --stepName load_cadd_scores.py --commit > $LOG_FILE_DIR/datasets/NG00122/preprocess_load_cadd_scores.log 2>&1

# load the data
loadResource -c $CONFIG_DIR/datasets/NG00122.json --load data --commit > $LOG_FILE_DIR/datasets/NG00122/load_result.log 2>&1


# NG00126
# -------------------------------------

mkdir $LOG_FILE_DIR/datasets/NG00126
loadResource -c $CONFIG_DIR/datasets/NG00126.json --verbose  --preprocess  --stepName GenomicsDBData::Load::Plugin::InsertStudy,GenomicsDBData::Load::Plugin::InsertProtocolAppNode --commit > $LOG_FILE_DIR/datasets/NG00126/placeholders.log 2>&1 

loadResource -c $CONFIG_DIR/datasets/NG00126.json --preprocess --stepName GenomicsDBData::GWAS::Plugin::LoadVariantGWASResult > $LOG_FILE_DIR/datasets/NG00126/preprocess_WGS_input.log 2>&1
loadResource -c $CONFIG_DIR/datasets/NG00126.json --preprocess --stepName GenomicsDBData::GWAS::Plugin::LoadVariantGWASResult > $LOG_FILE_DIR/datasets/NG00126/preprocess_WES_input.log 2>&1

loadResource -c $CONFIG_DIR/datasets/NG00126.json --preprocess --stepName db_map_variants.py --foreach WES > $LOG_FILE_DIR/datasets/NG00126/preprocess_WES_db_map_variants.log 2>&1
loadResource -c $CONFIG_DIR/datasets/NG00126.json --preprocess --stepName db_map_variants.py --foreach WGS > $LOG_FILE_DIR/datasets/NG00126/preprocess_WGS_db_map_variants.log 2>&1

# no WGS unmapped
loadResource -c $CONFIG_DIR/datasets/NG00126.json --preprocess --stepName load_vcf_file.py --foreach WES --commit > $LOG_FILE_DIR/datasets/NG00126/preprocess_WES_load_vcf_file.log 2>&1
loadResource -c $CONFIG_DIR/datasets/NG00126.json --preprocess --stepName file_map_variants.py --foreach WES > $LOG_FILE_DIR/datasets/NG00126/preprocess_WES_file_map_variants.log 2>&1
loadResource -c $CONFIG_DIR/datasets/NG00126.json --preprocess --stepName runVep --forech WES > $LOG_FILE_DIR/datasets/NG00126/preprocess_WES_runVep.log 2>&1
loadResource -c $CONFIG_DIR/datasets/NG00126.json --preprocess --stepName load_vep_result.py --foreach WES --commit > $LOG_FILE_DIR/datasets/NG00126/preprocess_WES_load_vep_result.log 2>&1
loadResource -c $CONFIG_DIR/datasets/NG00126.json --preprocess --stepName load_cadd_scores.py --foreach WES --commit > $LOG_FILE_DIR/datasets/NG00126/preprocess_WES_load_cadd_scores.log 2>&1

# load the data
loadResource -c $CONFIG_DIR/datasets/NG00126.json --load data --commit > $LOG_FILE_DIR/datasets/NG00126/load_result.log 2>&1

# GCST90027158
# -------------------------------------

mkdir $LOG_FILE_DIR/datasets/GCST90027158
loadResource --config $CONFIG_DIR/datasets/GCST90027158.json --load xdbr --commit > $LOG_FILE_DIR/datasets/GCST90027158/load_xdbr.log  2>&1
loadResource -c $CONFIG_DIR/datasets/GCST90027158.json --verbose  --preprocess  --stepName GenomicsDBData::Load::Plugin::InsertStudy,GenomicsDBData::Load::Plugin::InsertProtocolAppNode --commit > $LOG_FILE_DIR/datasets/GCST90027158/placeholders.log 2>&1 

loadResource -c $CONFIG_DIR/datasets/GCST90027158.json --preprocess --stepName GenomicsDBData::GWAS::Plugin::LoadVariantGWASResult > $LOG_FILE_DIR/datasets/GCST90027158/preprocess_input.log 2>&1

loadResource -c $CONFIG_DIR/datasets/GCST90027158.json --preprocess --stepName db_map_variants.py > $LOG_FILE_DIR/datasets/GCST90027158/preprocess_db_map_variants.log 2>&1

# pre-commit test
loadResource -c $CONFIG_DIR/datasets/GCST90027158.json --preprocess --stepName load_vcf_file.py > $LOG_FILE_DIR/datasets/GCST90027158/preprocess_load_vcf_file.log 2>&1
# all duplicates are indels that need to be switched (ref <-> alt)
loadResource -c $CONFIG_DIR/datasets/GCST90027158.json --preprocess --stepName load_vcf_file.py --params '{"logExisting":"false"}' --commit > $LOG_FILE_DIR/datasets/GCST90027158/preprocess_load_vcf_file.log 2>&1


loadResource -c $CONFIG_DIR/datasets/GCST90027158.json --preprocess --stepName file_map_variants.py  > $LOG_FILE_DIR/datasets/GCST90027158/preprocess_file_map_variants.log 2>&1
loadResource -c $CONFIG_DIR/datasets/GCST90027158.json --preprocess --stepName runVep  > $LOG_FILE_DIR/datasets/GCST90027158/preprocess_runVep.log 2>&1
loadResource -c $CONFIG_DIR/datasets/GCST90027158.json --preprocess --stepName load_vep_result.py --commit > $LOG_FILE_DIR/datasets/GCST90027158/preprocess_load_vep_result.log 2>&1
loadResource -c $CONFIG_DIR/datasets/GCST90027158.json --preprocess --stepName load_cadd_scores.py --commit > $LOG_FILE_DIR/datasets/GCST90027158/preprocess_load_cadd_scores.log 2>&1

# load the data
loadResource -c $CONFIG_DIR/datasets/GCST90027158.json --load data --commit > $LOG_FILE_DIR/datasets/GCST90027158/load_result.log 2>&1

# GWAS Catalog
# -------------------------------------

mkdir $LOG_FILE_DIR/reference/NHGRI
loadResource --config $CONFIG_DIR/reference_databases/gwas_catalog.json --load xdbr --commit > $LOG_FILE_DIR/reference/NHGRI/load_xdbr.log 2>&1
ga GUS::Supported::Plugin::LoadGusXml --file $PROJECT_HOME/GenomicsDBData/Load/lib/xml/update_gwas_catalog_external_db.xml --commit > $LOG_FILE_DIR/reference/NHGRI/placeholders.log 2>&1 

loadResource --config $CONFIG_DIR/reference_databases/gwas_catalog.json --preprocess --stepName clean_NHGRI_gwas_catalog.py > $LOG_FILE_DIR/reference/NHGRI/preprocess_clean.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/gwas_catalog.json --preprocess --stepName db_map_variants.py > $LOG_FILE_DIR/reference/NHGRI/preprocess_db_map_variants.log 2>&1

# Refresh Dataset MVs -- note: populationkeys MV will take some time to refresh
# -------------------------------------
psql -h $DB_HOST -U $DB_USER -d $DB_NAME --file /home/allenem/GRCh38/project_home/GenomicsDBData/Util/lib/sql/db_admin/scripts/refresh_niagads_mviews.sql 

# Manhattan plots
# -------------------------------------
manhattan.py --tracks GCST90027158,NG00126_WES,NG00126_WGS,NG00122 --outputPath $DATA_DIR/manhattan --fetchData --generatePlots --plotType all
# =================================================
# Garbage Collection
# =================================================

rm -r $LOG_FILE_DIR/datasets/NG00122
rm -r $DATA_DIR/NG00122

rm -r $LOG_FILE_DIR/datasets/NG00126
rm -r $DATA_DIR/NG00126