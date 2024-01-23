#!/usr/bin/env python3

import logging
import json
import argparse

from csv import DictReader
from os import path, environ
from sys import stdout
from multiprocessing import Pool, cpu_count
from enum import Enum

from AnnotatedVDB.Util.database.variant import VariantRecord
from niagads.utils.logging import ExitOnExceptionHandler
from niagads.utils.sys import verify_path, file_line_count
from niagads.utils.reg_ex import regex_replace
from niagads.utils.list import qw, chunker
from niagads.utils.string import eval_null, xstr
from niagads.utils.dict import print_dict

LOGGER = logging.getLogger(__name__)

CheckType = Enum('CheckType', ['NORMAL', 'UPDATE', 'FINAL'])
FileFormat = Enum('FileFormat', ['LOAD', 'LIST'])

INPUT_FIELDS = qw('chr bp allele1 allele2 marker metaseq_id freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json mapped_variant bin_index')


def init_worker(debug: bool):
    """initialize parallel worker with large data structures 
    or 'global' information'
    so they can be shared amongs the processors
    see https://superfastpython.com/multiprocessing-pool-shared-global-variables/

    Args:
        debug (bool): flag for debugging mode
    """
    # declare scope of new global variable
    global sharedDebugFlag   
    sharedDebugFlag = debug


def standardize_id(value):
    if value is not None:
        return value.replace('_', ':').replace('/', ':').replace('chr', '')
    return value


def build_variant_id(row, lineNum):
    LOGGER.debug(row)
    variantId = None
    marker = standardize_id(eval_null(row['marker']))
    metaseqId = standardize_id(eval_null(row['metaseq_id']))
    if args.useMarker:     
        if marker.count(':') == 3: # assume marker is metaseq_id
            variantId = marker
        else:
            variantId = ':'.join(marker, row['allele1'], row['allele2']) 
    else:        
        if metaseqId is None:
            chrom = eval_null(row['chr'])
            if chrom is None:
                if marker is None:
                    LOGGER.warning("Cannot generate variant ID from the following: " + xstr(row))
                    raise ValueError("metaseq_id, chromosome, marker and marker are all NULL - line number:" + str(lineNum))       
                variantId = ':'.join(marker, row['allele1', row['allele2']])
            else:
                variantId = ':'.join(chrom, row['bp'], row['allele1'], row['allele2'])
        else:
            variantId = metaseqId
    
    # if both alleles are unknown, drop alleles and just map against position
    variantId = regex_replace(':N:N', variantId) 
    return variantId


def parallel_db_lookup(lookups):
    # lookups is [{'variant': row}, {'variant2': row}, ... pairs]
    # to extract the variants, need to do the following:
    # [list(d) for d in lookups] -> [['variant'], '[variant2'], ...]; i.e. a nested list
    # unnested/flattened after: https://www.makeuseof.com/python-nested-list-flatten/
    # flatList = [k for i in nestedList for k in i]
    variants = [k for i in [list(d) for d in lookups] for k in i]
    variantStr = ','.join(variants)
    
    
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="", allow_abbrev=False)
    parser.add_argument('--inputFile', help="full path to input file", required=True)
    parser.add_argument('--format', choices=["LOAD", "LIST"], default="LOAD")
    parser.add_argument('--gusConfigFile', help="gus config file; defaults to $GUS_HOME/config/gus.config if not specified")
    parser.add_argument('--debug', action='store_true')
    parser.add_argument('--chunkSize', type=int, default=200)
    parser.add_argument('--useMarker', action='store_true')
    parser.add_argument('--checkType', choices = ["NORMAL", "UPDATE", "FINAL"], default="NORMAL")
    parser.add_argument('--numWorkers', help="number of workers for parallel processing, default = #CPUs - 2", 
                        type=int, default=cpu_count() - 2)
    
    args = parser.parse_args()

    logging.basicConfig(
        handlers=[ExitOnExceptionHandler(
            filename=args.inputFile + ".log",
            mode='w',
            encoding='utf-8',
        )],
        format='%(asctime)s %(funcName)s %(levelname)-8s %(message)s',
        level=logging.DEBUG if args.debug else logging.INFO
    )
    
    checkType = CheckType[args.checkType]
    
    numWorkers = args.numWorkers
    if numWorkers > cpu_count() - 2:
        LOGGER.warn("Invalid value for `numWorkers`" 
            + str(numWorkers), "must be <= #CPUS - 2: " 
            + str(cpu_count() - 2) + ": ADJUSTING")
        numWorkers = cpu_count() - 2
        

    outputFileName = args.inputFile + ".dbmapped.uc" \
        if checkType == CheckType.FINAL else args.inputFile + ".dbmapped"
    
    if verify_path(outputFileName):
        LOGGER.warn("DB Mapped file: " + outputFileName + " already exists; OVERWRITING")
    
    # create hash of variant_id -> line #
    # chunk the array keys (variant_id) and then run thru pool.imap
    
    numLines = file_line_count(args.inputFile, header=True)
    
    # create list of variant ids to look up
    # assumes variant_id is first column or only column
    with open(args.inputFile, 'r') as fh:
        if FileFormat[args.format] == FileFormat.LOAD:
            reader = DictReader(fh, delimiter='\t')
            header = reader.fieldnames
            # reader.line_num
            
            lookups = [] # using an array to keep order of file
            for row in reader:
                line = reader.line_num
                # array of variant_id : row pairs
                lookups.append({build_variant_id(row, line): row})

        else:
            raise NotImplementedError("DB Lookups for LISTs of variants not yet implemented")

    # rs88684912
    variant = list(lookups[0])
    annotator = VariantRecord()
    print("test - " + variant)
    result = annotator.bulk_lookup(variant)
    print_dict(result, pretty=True)

    # chunks = chunker(list(lookups), size=args.chunkSize)
    # with Pool(numWorkers, initializer=init_worker, initargs=(args.debug)) as pool:  
    #     if args.debug:
    #        LOGGER.debug("Starting parallel processing of variants; max number workers = " + str(numWorkers))
                
    #    mapping = pool.imap(parallel_db_lookup, [c for c in chunks])