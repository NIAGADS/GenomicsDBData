#!/usr/bin/env python3

import logging
import json
import argparse
import asyncio

from typing import List
from os import getcwd, path, remove as delete_file
from csv import DictReader
from enum import Enum
from math import modf
from pydantic import BaseModel

from niagads.utils.logging import ExitOnCriticalExceptionHandler
from niagads.utils.sys import verify_path, file_line_count, execute_cmd
from niagads.utils.reg_ex import regex_replace
from niagads.utils.list import qw, chunker
from niagads.utils.string import eval_null, xstr
from niagads.db.postgres import AsyncDatabase

LOGGER = logging.getLogger(__name__)


INPUT_FIELDS = qw('chr bp allele1 allele2 marker metaseq_id freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json mapped_variant bin_index')


def sort_file(fileName: str):
    sortedFileName = fileName + "-sorted.tmp"
    LOGGER.info("Sorting " + fileName)
    cmd = "(head -n 1 " + fileName + " && tail -n +2 " + fileName + " | sort -T " + args.outputDir + " -V -k1,1 -k2,2) > " + sortedFileName
    execute_cmd(cmd, shell=True)
    execute_cmd("mv " + sortedFileName + " " + fileName, shell=True)
    

def run():
    pass



if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="", allow_abbrev=False)
    parser.add_argument('--inputFile', help="full path to input file", required=True)
    parser.add_argument('--idMap', help="metaseq -> pk map", required=True)
    parser.add_argument('--debug', action='store_true')
    parser.add_argument('--verbose', action='store_true')
    parser.add_argument('--log2stderr', action="store_true", help="log to stderr instead of a file")
                        
    args = parser.parse_args()
    
    
    logFileName = path.join(args.outputDir, path.basename(args.inputFile) + "-file-based-mapping.log")
    logHandler = logging.StreamHandler() if args.log2stderr \
        else ExitOnCriticalExceptionHandler(
                filename=logFileName,
                mode='w',
                encoding='utf-8',
            )
    logging.basicConfig(
        handlers=[logHandler],
        format='%(asctime)s %(funcName)s %(levelname)-8s %(message)s',
        level=logging.DEBUG if args.debug else logging.INFO
    )
    try:
        
        mappingFileName = run()

        LOGGER.info("Sorting mapping file: " + mappingFileName) 
        sort_file(mappingFileName)
        
        LOGGER.info("SUCCESS")
        
    except Exception as err:

        LOGGER.critical(str(err), stack_info=True, exc_info=True)
