#!/usr/bin/bash

# Adapted from 
# https://serverfault.com/questions/682708/copy-directory-structure-intact-to-aws-s3-bucket
# usage: s3_recursiveCopy.sh  <directory on local server> <s3 bucket path>
path=$1 # the path of the directory where the files and directories that need to be copied are located, must not end in /
s3Dir=$2 # the s3 bucket path; must not end in /

for entry in "$path"/*; do
    name=`echo $entry | sed 's/.*\///'`  # getting the name of the file or directory
    if [[ -d  $entry ]]; then  # if it is a directory
        aws s3 cp  --recursive "$entry" "$s3Dir/$name/"
    else  # if it is a file
        aws s3 cp "$entry" "$s3Dir/"
    fi
done
