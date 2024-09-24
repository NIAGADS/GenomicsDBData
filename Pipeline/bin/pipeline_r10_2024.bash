
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
loadResource -c $CONFIG_DIR/datasets/NG00122.json --preprocess --stepName  db_map_variants.py > $LOG_FILE_DIR/datasets/NG00122/preprocess_db_map.log 2>&1

loadResource -c $CONFIG_DIR/datasets/NG00122.json --preprocess --stepName  run_vep > $LOG_FILE_DIR/datasets/NG00122/vep.log 2>&1




oadResource -c $CONFIG_DIR/datasets/NG00122.json --load data --params '{"load":"true", "genomeBuild":"GRCh38", "commitAfter":"50000"}' --verbose --commit > $LOG_FILE_DIR/datasets/NG00122/load_result.log 2>&1
loadResource -c $CONFIG_DIR/datasets/NG00122.json  --load data --params '{"genomeBuild":"GRCh38", "standardize":"true"}' --verbose > $LOG_FILE_DIR/datasets/NG00122/GRCh38_standardize.log 2>&1

loadResource -c $CONFIG_DIR/datasets/NG00122.json  --load data --params '{"genomeBuild":"GRCh38", "archive":"true"}' --verbose > $LOG_FILE_DIR/datasets/NG00122/GRCh38_archive.log 2>&1
gzip $SHARED_DATA_DIR/NIAGADS/GRCh38/NG00122/GRCh38/*.txt
gzip $LOG_FILE_DIR/datasets/NG00122/*.log

tar -zcvf GRCh38.tar.gz --directory $SHARED_DATA_DIR/NIAGADS/GRCh38/NG00122 GRCh38
rm -r $SHARED_DATA_DIR/NIAGADS/GRCh38/NG00122/GRCh38