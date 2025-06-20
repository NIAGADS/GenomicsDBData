# OUTPUT_PATH=$2
# TRACK=$1

OUTPUT_PATH=$DATA_DIR/NIAGADS/exports

ACCESSIONS=("NG00126" "NG00122" "NG00045" "GCST90027158" "NG00027" "NG00036" "NG00039" "NG00040" "NG00048" "NG00049" "NG00052" "NG00053" "NG00055" "NG00056" "NG00058" "NG00073" "NG00075" "NG00076" "NG00078" "NG00115")
TRACKS=("NG00126_WES,NG00126_WGS" "NG00122" "NG00045_GRCh38_EUR_STAGE12,NG00045_GRCh38_STAGE12,NG00045_GRCh38_EUR_STAGE1,NG00045_GRCh38_STAGE1" "GCST90027158" "NG00027_GRCh38_ADJ_STAGE1,NG00027_GRCh38_ADJ_STAGE12,NG00027_GRCh38_ADJ_STAGE2,NG00027_GRCh38_STAGE12,NG00027_GRCh38_STAGE1,NG00027_GRCh38_STAGE2" "NG00036_GRCh38_STAGE1,NG00036_GRCh38_STAGE12" "NG00039_GRCh38,NG00039_GRCh38_ADJ" "NG00040_GRCh38_AD,NG00040_GRCh38_PSP,NG00040_GRCh38_FTD" "NG00048_GRCh38" "NG00049_GRCh38_AB42,NG00049_GRCh38_TAU,NG00049_GRCh38_PTAU" "NG00052_GRCh38" "NG00053_GRCh38" "NG00055_AB42,NG00055_GRCh38_TAU,NG00055_GRCh38_PTAU" "NG00056_GRCh38_ALL,NG00056_GRCh38_APOE_E4,NG00056_GRCh38_NON_APOE_E4,NG00056_GRCh38_ALL_APOE_ADJ" "NG00058_GRCh38" "NG00073_GRCh38_MEM,NG00073_GRCh38_VSP,NG00073_GRCh38_LANG,NG00073_GRCh38_NONE,NG00073_GRCh38_MIX" "NG00075_GRCh38_STAGE1,NG00075_GRCh38_STAGE2" "NG00076_GRCh38"  "NG00078_GRCh38_ALL,NG00078_GRCh38_APOE4_CARRIERS,NG00078_GRCh38_APOE4_NON_CARRIERS,NG00078_GRCh38_INT" "NG00115_GRCh38_MALE,NG00115_GRCh38_FEMALE")

NG00041_ACCESSION=("NG00041")
NG00041_TRACKS=("NG00041_GRCh38_LEWY" "NG00041_GRCh38_NP_CONS" "NG00041_GRCh38_CAA" "NG00041_GRCh38_LEWY_5" "NG00041_GRCh38_NP_RELAX" "NG00041_GRCh38_NFT_BGROUPS" "NG00041_GRCh38_HS" "NG00041_GRCh38_STATUS" "NG00041_GRCh38_NFT_BSTAGES" "NG00041_GRCh38_NP" "NG00041_GRCh38_VBI" "NG00041_GRCh38_LEWY_3" "NG00041_GRCh38_NP_CERAD" "NG00041_GRCh38_VBI_3")
#NG00041_TRACKS=("NG00041_GRCh38_STATUS" "NG00041_GRCh38_NFT_BSTAGES" "NG00041_GRCh38_NP" "NG00041_GRCh38_VBI" "NG00041_GRCh38_LEWY_3" "NG00041_GRCh38_NP_CERAD" "NG00041_GRCh38_VBI_3")


# Function to simulate some work
do_work() {
   echo "Starting job: $1 - $2 - $3"
   export_summary_statistics.py --accession $1 -o $OUTPUT_PATH  --track $2 --fastaRefDir $DATA_DIR/FASTA > ${3}.log 2>&1 
   echo "Finished job: $1 - $2"
}

# Number of jobs to run in parallel
num_parallel=20

# Counter for running jobs
running_jobs=0

mkdir $OUTPUT_PATH/NG00041 # have to create this otherwise get a race condition when the script tries to create it
for TID in  "${NG00041_TRACKS[@]}"; do
  # If we have reached the limit of parallel jobs, wait for one to finish
  if [ "$running_jobs" -ge "$num_parallel" ]; then
    wait -n # Wait for the next job to complete
    ((running_jobs--)) # Decrement the counter
  fi

  # Run the job in the background
  do_work NG00041 $TID "NG00041-${TID}" &
  ((running_jobs++)) # Increment the counter
done


NUM_ACCESSIONS=${#ACCESSIONS[@]}
for (( i=0; i<${NUM_ACCESSIONS}; i++ )); do
  # If we have reached the limit of parallel jobs, wait for one to finish
  if [ "$running_jobs" -ge "$num_parallel" ]; then
    wait -n # Wait for the next job to complete
    ((running_jobs--)) # Decrement the counter
  fi

  # Run the job in the background
  do_work ${ACCESSIONS[$i]} ${TRACKS[$i]} ${ACCESSIONS[$i]} &
  ((running_jobs++)) # Increment the counter
done


echo "All jobs finished."









# if [ "${TRACK}" = "NG00041" ] then
#     NUM_TRACKS=${#ACCESSIONS[@]}
#     for TID in  "${NG00041_TRACKS[@]}"
#     do
#         export_summary_statistics.py --accession NG00041 --track "${TID}" -o $OUTPUT_PATH > ${TID}.log 2>&1 &
#     done
# else
#     NUM_ACCESSIONS=${#ACCESSIONS[@]}
#     for (( i=0; i<${NUM_ACCESSIONS}; i++ ));
#     do
#         export_summary_statistics.py --accession ${ACCESSIONS[$i]} --track "${TRACKS[$i]}" -o $OUTPUT_PATH > ${TID}.log 2>&1 &
#     done
# fi


	