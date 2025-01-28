#!/bin/bash

FILE=$1
INPUT_FILE=${FILE}
OUTPUT_FILE=${INPUT_FILE}.vep.json.gz
ERROR_FILE=${INPUT_FILE}.vep.errors
LOG_FILE=${INPUT_FILE}.vep.log

if 
$VEP_HOME/vep \
  --input_file $INPUT_FILE \
  --output_file $OUTPUT_FILE \
  --format vcf \
  --compress_output gzip \
  --cache \
  --dir_cache $VEP_CACHE_DIR \
  --dir_plugins $VEP_CACHE_DIR/plugins \
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
  --af_gnomadg \
  --af_gnomade \
  --pubmed \
  --clin_sig_allele 1 \
  --nearest gene \
  --gene_phenotype \
  --plugin TSSDistance \
  --force_overwrite \
  --verbose \
  --warning_file  $ERROR_FILE 


then
    echo "SUCCESS"
else
    echo "FAIL"
fi
