#!/bin/bash

# Function to simulate some work
do_work() {
   echo "Starting job: $1"
   db_map_variants.py --inputFile $1 --outputDir /mnt/efs/trx/genomicsdb/data/GRCh38/ADSP/FunGen_QTL/preprocess --maxConnections 10 --logAfter 10000 --chunkSize 1000 --overwrite --log2stderr > $1-db_map.log 2>&1
   echo "Finished job: $1"
}

# Number of jobs to run in parallel
num_parallel=5

# Counter for running jobs
running_jobs=0

files=($(ls *-input.txt))

# Loop through the job

for file in ${files[@]}; do
  # If we have reached the limit of parallel jobs, wait for one to finish
  if [ "$running_jobs" -ge "$num_parallel" ]; then
    wait -n # Wait for the next job to complete
    ((running_jobs--)) # Decrement the counter
  fi

  # Run the job in the background
  do_work "$file" &
  ((running_jobs++)) # Increment the counter
done

# Wait for any remaining jobs to complete
wait

echo "All jobs finished."
