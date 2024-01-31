#!/usr/bin/env python3

import logging
import json
import argparse

from csv import DictReader
from multiprocessing import Pool, cpu_count
from enum import Enum
from math import modf

from AnnotatedVDB.Util.database.variant import VariantRecord
from niagads.utils.logging import ExitOnCriticalExceptionHandler
from niagads.utils.sys import verify_path, file_line_count
from niagads.utils.reg_ex import regex_replace
from niagads.utils.list import qw, chunker
from niagads.utils.string import eval_null, xstr
from niagads.utils.dict import print_dict

LOGGER = logging.getLogger(__name__)

CheckType = Enum('CheckType', ['NORMAL', 'UPDATE', 'FINAL'])
FileFormat = Enum('FileFormat', ['LOAD', 'LIST'])

INPUT_FIELDS = qw('chr bp allele1 allele2 marker metaseq_id freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json mapped_variant bin_index')


def init_worker(debug: bool, firstHitOnly: bool):
    """initialize parallel worker with large data structures 
    or 'global' information'
    so they can be shared amongs the processors
    see https://superfastpython.com/multiprocessing-pool-shared-global-variables/

    Args:
        debug (bool): flag for debugging mode
    """
    # declare scope of new global variable
    global sharedDebugFlag   
    global sharedFirstHitOnlyFlag
    sharedDebugFlag = debug
    sharedFirstHitOnlyFlag = firstHitOnly


def standardize_id(value):
    if value is not None:
        return value.replace('_', ':').replace('/', ':').replace('chr', '')
    return value


def mapping_to_string(value):
    if value is None:
        return "NULL"
    if isinstance(value, str) and value.lower() == "null":
        return "NULL"
    return json.dumps(value)


def build_variant_id(row, lineNum):
    variantId = None
    marker = standardize_id(eval_null(row['marker']))
    metaseqId = standardize_id(eval_null(row['metaseq_id']))
    if args.useMarker:     
        if marker.count(':') == 3: # assume marker is metaseq_id
            variantId = marker
        else:
            variantId = ':'.join((marker, row['allele1'], row['allele2']) )
    else:        
        if metaseqId is None:
            chrom = eval_null(row['chr'])
            bp = eval_null(row['bp'])
            if bp is None:
                if marker is None:
                    LOGGER.warning("Cannot generate variant ID from the following: " + xstr(row))
                    if args.failOnInvalidVariant:
                        raise ValueError("metaseq_id, and BP are NULL - line number:" + str(lineNum))      
                    # else:
                    #     return None
            if chrom is None:
                if marker is None:
                    LOGGER.warning("Cannot generate variant ID from the following: " + xstr(row))
                    if args.failOnInvalidVariant:
                        raise ValueError("metaseq_id, chromosome, marker and marker are all NULL - line number:" + str(lineNum))  
                    # else:
                    #    return None     
                variantId = ':'.join((marker, row['allele1', row['allele2']]))
            else:
                variantId = ':'.join((chrom, row['bp'], row['allele1'], row['allele2']))
        else:
            variantId = metaseqId
    
    # if both alleles are unknown, drop alleles and just map against position
    variantId = regex_replace(':N:N', '', variantId) 
    return variantId


def catch_db_lookup_error(variants, lookups, firstHitOnly):
    annotator = VariantRecord(debug=args.debug)
    result = {}
    for index, variant in enumerate(variants):
        try:
            result.update(annotator.bulk_lookup(variant, fullAnnotation=False, firstHitOnly=firstHitOnly))
        except Exception as err:
            result.update({variant, {'error': str(err), 'input': lookups[index].values()[0]} })
    
    return result

            
def parallel_db_lookup(lookups):
    global sharedFirstHitOnlyFlag
    # lookups is [{'variant': row}, {'variant2': row}, ... pairs]
    # to extract the variants, need to do the following:
    # [list(d) for d in lookups] -> [['variant'], '[variant2'], ...]; i.e. a nested list
    # unnested/flattened after: https://www.makeuseof.com/python-nested-list-flatten/
    # flatList = [k for i in nestedList for k in i]
    variants = [k for i in [list(d) for d in lookups] for k in i]
    try:
        annotator = VariantRecord(debug=args.debug)
        mappings = annotator.bulk_lookup(variants, fullAnnotation=False, firstHitOnly=sharedFirstHitOnlyFlag)     
        return {"lookups" :lookups, "mappings": mappings }
    except Exception as err:
        LOGGER.warning("ERROR with bulk lookup; finding problematic variant")
        return catch_db_lookup_error(variants, lookups, sharedFirstHitOnlyFlag)


def initialize():
    logFileName = args.inputFile + ".log"
    logging.basicConfig(
        handlers=[ExitOnCriticalExceptionHandler(
            filename= logFileName,
            mode='w',
            encoding='utf-8',
        )],
        format='%(asctime)s %(funcName)s %(levelname)-8s %(message)s',
        level=logging.DEBUG if args.debug else logging.INFO
    )
    
    LOGGER.info("Logging to: " + logFileName)
    
    checkType = CheckType[args.checkType]
    LOGGER.info("Check Type: " + checkType.name)
    
    numWorkers = args.numWorkers
    if numWorkers > cpu_count() - 2:
        LOGGER.warning("Invalid value for `numWorkers`" 
            + str(numWorkers), "must be <= #CPUS - 2: " 
            + str(cpu_count() - 2) + ": ADJUSTING")
        numWorkers = cpu_count() - 2
        
    LOGGER.info("Num workers: " + str(numWorkers))

    outputFileName = args.inputFile + ".dbmapped.uc" \
        if checkType == CheckType.FINAL else args.inputFile + ".dbmapped"
        
    LOGGER.info("Writing DB-mapped variants to: " + outputFileName)
    
    if verify_path(outputFileName):
        LOGGER.warning("DB Mapped file: " + outputFileName + " already exists; OVERWRITING")
    
    # create hash of variant_id -> line #
    # chunk the array keys (variant_id) and then run thru pool.imap
    
    numLines = file_line_count(args.inputFile, header=True)
    LOGGER.info("Estimated Lines in Input File: " + str(numLines))
    LOGGER.info("Chunk Size = " + str(args.chunkSize))
    
    if args.test:
        if args.test > numLines:
            raise ValueError("TEST size > # lines in file")
        LOGGER.info("Running in TEST mode; processing : " + str(args.test) + " lines.")
        f, i  = modf(args.test / args.chunkSize)
        LOGGER.info("Estimated paged lookups: " + (str(int(i) + 1) if f > 0 else str(int(i))))
    else:
        f, i = modf(numLines / args.chunkSize)
        LOGGER.info("Estimated paged lookups: " + (str(int(i) + 1) if f > 0 else str(int(i))))
        
    return numWorkers, outputFileName


def parse_input_file():
    lineCount = 0
    header = None
    with open(args.inputFile, 'r') as fh:
        if FileFormat[args.format] == FileFormat.LOAD:
            reader = DictReader(fh, delimiter='\t')
            header = reader.fieldnames
            lookups = [] # using an array to keep order of file
            for row in reader:
                lineCount = lineCount + 1
                # array of variant_id : row pairs
                lookups.append({build_variant_id(row, lineCount): row})
                if args.test and lineCount == args.test:
                    LOGGER.info("Done reading in test lines: n = " + xstr(args.test))
                    break
                
                if args.verbose and lineCount % 500000 == 0:
                    LOGGER.info("Read " + str(lineCount) + " lines.")

        else:
            raise NotImplementedError("DB Lookups for LISTs of variants not yet implemented")

    LOGGER.info("Done reading file.  Parsed " + str(lineCount) + " lines.")
    
    return header, lookups


def run(outputFileName, numWorkers, header, lookups):
    if args.verbose:
        LOGGER.info("Starting parallel processing of variants; max number workers = " + str(numWorkers))
        
    with open(outputFileName, 'w') as ofh, \
        Pool(numWorkers, initializer=init_worker, initargs=(args.debug, not args.allHits)) as pool: 

        lineCount = 0
        errorCount = 0
        header = header + ['db_mapped_variant']
        print('\t'.join(header), file=ofh)
        
        chunks = chunker(list(lookups), size=args.chunkSize, returnIterator=False)
        result = pool.imap(parallel_db_lookup, [c for c in chunks])        
        
        for r in result:           
            lookups = r['lookups']
            mappings = r['mappings']
            for item in lookups:
                variant = list(item.keys())[0]
                row = list(item.values())[0]
                mappedVariant = mappings[variant]
                if mappedVariant is None:
                    # TODO: print Nones to unmapped file
                    LOGGER.debug("Unmapped Variant: " + print_dict({'variant': variant, 'row': row}))
                elif 'error' in mappedVariant:
                    errorCount = errorCount + 1
                    LOGGER.error("Unable to map variant: " + print_dict(mappedVariant))
                else:
                    
                    row['db_mapped_variant'] = mapping_to_string(mappings[variant])
                    print('\t'.join([ row[field] for field in header]), file = ofh)
                    lineCount = lineCount + 1
                    if args.verbose and lineCount % 500000 == 0:
                        LOGGER.info("Wrote " + str(lineCount) + " updated lines.")

    LOGGER.info("Wrote " + str(lineCount) + " updated lines.")    
    LOGGER.info("Error mapping " + str(errorCount) + " variants; see log file.")      
    # LOGGER.info("Unable to map " + str(unmappedCount) + " variants; see " + unmappedFileName) 
    # LOGGER.info("Skipped " + str(invalidCount)) + " invalid variants; see log file.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="", allow_abbrev=False)
    parser.add_argument('--inputFile', help="full path to input file", required=True)
    parser.add_argument('--format', choices=["LOAD", "LIST"], default="LOAD")
    parser.add_argument('--gusConfigFile', help="gus config file; defaults to $GUS_HOME/config/gus.config if not specified")
    parser.add_argument('--debug', action='store_true')
    parser.add_argument('--verbose', action='store_true')
    parser.add_argument('--chunkSize', type=int, default=200)
    parser.add_argument('--failOnInvalidVariant', action='store_true', help="fail when invalid variants found, otherwise logs & skips")
    parser.add_argument('--useMarker', action='store_true')
    parser.add_argument('--allHits', action='store_true', help="return all hits to a marker; if not specified will return first hit only")
    parser.add_argument('--checkType', choices = ["NORMAL", "UPDATE", "FINAL"], default="NORMAL")
    parser.add_argument('--test', help="test run, supply # of lines to read from input file", type=int)
    parser.add_argument('--numWorkers', help="number of workers for parallel processing, default = #CPUs - 2", 
                        type=int, default=cpu_count() - 2)
    
    args = parser.parse_args()

    try:
        numWorkers, outputFileName = initialize()
        header, lookups = parse_input_file()
        run(outputFileName, numWorkers, header, lookups)
    except Exception as err:
        LOGGER.critical("DB mapping FAILED: ", err, stack_info=True)
