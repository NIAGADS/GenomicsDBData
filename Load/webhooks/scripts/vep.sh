#!/bin/bash
#PBS -l h_vmem=8G


PLUGIN_DIR=$VEP_PLUGIN_DIR
CACHE_DIR=$VEP_CACHE_DIR

export PERL5LIB=$PERL5LIB:$PLUGIN_DIR


while getopts f: OPTION
do
    case "${OPTION}" in
        f) FILE=${OPTARG};;
    esac
done


INPUT_FILE=${NIAGADS_GWAS_DIR}/${FILE}
OUTPUT_FILE=${INPUT_FILE}.vep.json.gz
ERROR_FILE=${INPUT_FILE}.vep.errors
LOG_FILE=${INPUT_FILE}.vep.log

if
vep \
  --input_file $INPUT_FILE \
  --output_file $OUTPUT_FILE \
  --format vcf \
  --compress_output gzip \
  --dir_cache $CACHE_DIR \
  --cache \
  --offline \
  --no_stats \
  --json \
  --fork 4 \
  --sift b \
  --polyphen b \
  --ccds \
  --symbol \
  --numbers \
  --domains \
  --regulatory \
  --canonical \
  --protein \
  --biotype \
  --tsl \
  --pubmed \
  --uniprot \
  --variant_class \
  --exclude_predicted \
  --gencode_basic \
  --af \
  --af_1kg \
  --af_esp \
  --af_gnomad \
  --clin_sig_allele 1 \
  --nearest gene \
  --gene_phenotype \
  --plugin TSSDistance \
  --force_overwrite \
  --warning_file  $ERROR_FILE \
  --verbose

then
    echo "SUCCESS"
else
    echo "FAIL"
fi
