#!/usr/bin/env python3

import logging
import argparse
import csv 

from os import path


from niagads.utils.logging import ExitOnCriticalExceptionHandler
from niagads.utils.sys import rename_file
from niagads.utils.reg_ex import regex_replace
from niagads.utils.list import qw, chunker
from niagads.utils.string import eval_null, xstr


LOGGER = logging.getLogger(__name__)

def read_mapping():
    LOGGER.info("Parsing Mapping File: %s", args.idMap)
    
    mapping = None
    with open(args.idMap, 'r') as fh:
        reader = csv.reader(fh, delimiter='\t')
        mapping = dict(reader)
    LOGGER.info("Read %s variants", len(mapping))
    
    if args.debug:
        LOGGER.debug("id mapping check: %s", dict(list(mapping.items())[0:10])
)
    
    return mapping

def run():
    idMap = read_mapping()    
    
    with open(args.inputFile, 'r') as fh, open(args.inputFile + '.tmp', 'w') as tfh:
        reader = csv.DictReader(fh, delimiter='\t')
        
        writer = csv.DictWriter(tfh, delimiter='\t', fieldnames = reader.fieldnames)
        writer.writeheader()
        
        mappedCount = 0
        lineCount = 0
        for row in reader:
            lineCount = lineCount + 1
            if row['db_mapped_variant'] == 'NULL':
                try: 
                    row['db_mapped_variant'] = idMap[row['metaseq_id']]
                    mappedCount = mappedCount + 1
                except KeyError as err:
                    LOGGER.critical("Variant not mapped: %s", row['metaseq_id'] )
                    raise(err)   
            
            if lineCount % 1000000 == 0:
                LOGGER.info("Parsed %s lines; mapped %s variants", lineCount, mappedCount)  

            writer.writerow(row)

    LOGGER.info("DONE: Mapped %s variants", mappedCount)
    LOGGER.info("Backing up old mapping file %s and replacing", args.inputFile)
    rename_file(args.inputFile + '.tmp', args.inputFile, backupExistingTarget=True)
            


if __name__ == "__main__":
    
    parser = argparse.ArgumentParser(description="", allow_abbrev=False)
    parser.add_argument('--inputFile', help="full path to input file", required=True)
    parser.add_argument('--idMap', help="metaseq -> pk map", required=True)
    parser.add_argument('--debug', action='store_true')
    parser.add_argument('--verbose', action='store_true')
    parser.add_argument('--log2stderr', action="store_true", help="log to stderr instead of a file")
                        
    args = parser.parse_args()
    
    
    logFileName = path.join(args.inputFile + "-file-based-mapping.log")
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

        run()

        LOGGER.info("SUCCESS")
        
    except Exception as err:
        raise(err)