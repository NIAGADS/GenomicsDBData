#!/usr/bin/env python3

import logging
import json
import argparse
import asyncio

from os import getcwd, path
from csv import DictReader
from enum import Enum
from math import modf
from sys import exc_info

from niagads.utils.logging import ExitOnCriticalExceptionHandler
from niagads.utils.sys import verify_path, file_line_count
from niagads.utils.reg_ex import regex_replace
from niagads.utils.list import qw, chunker
from niagads.utils.string import eval_null, xstr
from niagads.utils.dict import print_dict
from niagads.db.postgres import AsyncDatabase


LOGGER = logging.getLogger(__name__)

NORMALIZE_CHUNK_SIZE = 20
NORMALIZE_MAX_CONNECTIONS = 10
BULK_LOOKUP_SQL = "SELECT * from map_variants($1, $2, $3, $4) AS mappings"; # second param is "firstValueOnly flag", then checkAltVariants

CheckType = Enum('CheckType', ['NORMAL', 'UPDATE', 'FINAL'])
FileFormat = Enum('FileFormat', ['LOAD', 'LIST'])

INPUT_FIELDS = qw('chr bp allele1 allele2 marker metaseq_id freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json mapped_variant bin_index')


def check_file(extension, fileType, suffix):    
    baseName = path.basename(args.inputFile)
    filePath = path.join(args.outputDir, baseName + suffix + '.' + extension)
    LOGGER.info(fileType + ": " + filePath)
    if verify_path(filePath):
        LOGGER.warning(fileType + " : already exists; OVERWRITING")
    return filePath


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


def build_variant_id(row):
    variantId = None
    marker = standardize_id(eval_null(row['marker']))
    metaseqId = standardize_id(eval_null(row['metaseq_id']))
    isIndel = False
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
                if args.failOnInvalidVariant:
                    raise ValueError("metaseq_id and BP are NULL - line number:" + xstr(row))
                else:
                    if args.verbose:
                        LOGGER.warning("Cannot generate variant ID from the following: " + xstr(row))
                    return None, isIndel
            if chrom is None:
                if args.failOnInvalidVariant:
                    raise ValueError("metaseq_id and chromosome are NULL - line number:" + xstr(row))  
                else:
                    if args.verbose:
                        LOGGER.warning("Cannot generate variant ID from the following: " + xstr(row))
                    return None, isIndel

            variantId = ':'.join((chrom, bp, row['allele1'], row['allele2']))
            isIndel = len(row['allele1']) != len(row['allele2']) # i.e., not SNV or MNV
        else:
            variantId = metaseqId
            c, p, r, a = metaseqId.split(':')
            # not an SNV / MNV and len(ref) || len(alt) > expected length e.g., 2  - so that AC:T or CG:A will be treated as SNV in lookups
            isIndel = len(r) != len(a) and (len(r) > args.indelLength or len(a) > args.indelLength)
    
    # if both alleles are unknown, drop alleles and just map against position
    variantId = regex_replace(':N:N', '', variantId) 
    return variantId, isIndel


def initialize():
    suffix = '' if not args.outputSuffix else '-' + args.outputSuffix
    
    logFileName = path.join(args.outputDir, path.basename(args.inputFile) + suffix + ".log")
    logging.basicConfig(
        handlers=[ExitOnCriticalExceptionHandler(
            filename= logFileName,
            mode='w',
            encoding='utf-8',
        )],
        format='%(asctime)s %(funcName)s %(levelname)-8s %(message)s',
        level=logging.DEBUG if args.debug else logging.INFO
    )
    
    LOGGER.info("SETTINGS")
    
    checkType = CheckType[args.checkType]
    LOGGER.info("Check Type: " + checkType.name)
            
    if args.maxConnections > 50:
        LOGGER.warning("maxConnections too high, setting to 50")
        args.maxConnections = 50
    LOGGER.info("Max number of threads: " + str(args.maxConnections))
    
    args.mappedFile = check_file("map", "DB mapped variants file", suffix)
    args.unmappedFile = check_file("unmap" , "Unmapped DB mapped variants file", suffix)
    args.skipFile = check_file("skip", "Skipped variants file", suffix)
    args.errorFile = check_file("error", "DB mapping Error file", suffix)
    
    # create hash of variant_id -> line #   
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
    
    return args


def parse_input_file():
    lineCount = 0
    skipCount = 0
    header = None
    with open(args.inputFile, 'r') as fh, \
        open(args.skipFile, 'w') as sfh:
            
        if FileFormat[args.format] == FileFormat.LOAD:
            reader = DictReader(fh, delimiter='\t')
            header = reader.fieldnames
            
            print('\t'.join(header), file=sfh)
            
            variants = [] # using array in case of multiple rows mapped to same variant
            indels = []
            for row in reader:
                lineCount = lineCount + 1
                
                variantId, isIndel = build_variant_id(row)
                
                if variantId is None:
                    print('\t'.join([row[field] for field in header]), file = sfh)   
                    skipCount = skipCount + 1
                else:                   
                    if isIndel:
                        # indels will be processed separately b/c lookup time may be longer
                        # speeds things up and allows to not checkAltIndels if keepIndelDirection is specified
                        indels.append({variantId: row})
                    else:
                        variants.append({variantId: row})

                if args.test and lineCount == args.test:
                    LOGGER.info("Done reading in test lines: n = " + xstr(args.test))
                    break
                
                if lineCount % 500000 == 0:
                    LOGGER.info("Read " + str(lineCount) + " lines.")

        else:
            raise NotImplementedError("DB Lookups for LISTs of variants not yet implemented")

    LOGGER.info("Done reading file.  Parsed " + str(lineCount) + " lines.")
    
    return { 'header': header, 'variants': variants, 'indels': indels, 'skipped': skipCount}


async def db_lookup(lookups, semaphore: asyncio.Semaphore, firstHitOnly=True, checkAltVariants=True, normalize=False):
    async with semaphore:
        try:
            annotator = AsyncDatabase(connectionString=args.connectionString)
            await annotator.connect()
            connection = annotator.connection()
            
            variants = [k for i in [list(d) for d in lookups] for k in i]
            mappings = await connection.fetchval(BULK_LOOKUP_SQL,
                ','.join(variants),
                firstHitOnly, checkAltVariants, normalize,
                column=0)
            
            return {"lookups" :lookups, "mappings": mappings }

        finally:
            await annotator.close()


async def run(header, lookups, chunkSize, maxConnections = NORMALIZE_MAX_CONNECTIONS,
    checkAltVariants=True, checkNormalizedAlleles=False, append=False):

    LOGGER.info("Starting parallel processing; max number workers = " + str(maxConnections) + "; chunk size = " + str(chunkSize))
    
    writeType = 'a' if append else 'w'

    mappedHeader = header + ['db_mapped_variant']
    mCount = 0
    count = 0
    errors = []
    unmapped = []
    
    with open(args.mappedFile, writeType) as mfh, \
        open(args.errorFile, writeType) as efh:
            
        if not append:
            print('\t'.join(mappedHeader), file=mfh)
            print('\t'.join(header), file=efh)
                            
        semaphore = asyncio.Semaphore(maxConnections)
        chunks = chunker(list(lookups), size=chunkSize, returnIterator=False)
        tasks = [db_lookup(c, semaphore, firstHitOnly=not args.allHits, 
            checkAltVariants=checkAltVariants, normalize=checkNormalizedAlleles) for c in chunks]
        for task in asyncio.as_completed(tasks):
            result = await task

            lookups = result['lookups']
            mappings = result['mappings']
            for item in lookups:
                count = count + 1
                variant = list(item.keys())[0]
                row = list(item.values())[0]
                mappedVariant = mappings[variant]
                if mappedVariant is None:
                    unmapped.append(item)
                elif 'error' in mappedVariant:
                    print('\t'.join([ row[field] for field in header]), file = efh)   
                    errors.append(mappedVariant)
                else:      
                    row['db_mapped_variant'] = mapping_to_string(mappings[variant])
                    print('\t'.join([ row[field] for field in mappedHeader]), file = mfh)
                    mCount = mCount + 1
                
                if count % args.logAfter == 0:
                    LOGGER.info("Processed " + str(count) + " variants.")
                
    LOGGER.info("Processed " + str(count) + " variants.")    
    return {'count': mCount, 'unmapped': unmapped, 'errors': errors}


def write_unmapped_variants(header, variants):
    with open(args.unmappedFile, 'w') as fh:
        print('\t'.join(header), file=fh)
        for item in variants:
            variant = list(item.keys())[0]
            row = list(item.values())[0]
            print('\t'.join([ row[field] for field in header]), file = fh)   
            if args.debug and args.verbose:
                LOGGER.debug("Unmapped Variant: " + xstr({'variant': variant, 'row': row}))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="", allow_abbrev=False)
    parser.add_argument('--inputFile', help="full path to input file", required=True)
    parser.add_argument('--outputSuffix', help="suffix to append to output files to prevent overwriting; for debug/testing")
    parser.add_argument('--outputDir', default=getcwd(), help="full path to output directory; if not specified will use current working directory")
    parser.add_argument('--format', choices=["LOAD", "LIST"], default="LOAD")
    parser.add_argument('--gusConfigFile', help="gus config file; defaults to $GUS_HOME/config/gus.config if not specified")
    parser.add_argument('--debug', action='store_true')
    parser.add_argument('--verbose', action='store_true')
    parser.add_argument('--chunkSize', type=int, default=5000)
    parser.add_argument('--indelLength', type=int, default=2, help="length of variant considered to be a 'long' INDEL")
    parser.add_argument('--failOnInvalidVariant', action='store_true', help="fail when invalid variants found, otherwise logs & skips")
    # parser.add_argument('--failOnDbLookupError', action='store_true', help="fail instead of logging DB variant lookup error")
    parser.add_argument('--useMarker', action='store_true')
    parser.add_argument('--keepIndelDirection', action='store_true', help="if specified will not check alt allele configurations for INDELs")
    parser.add_argument('--allHits', action='store_true', help="return all hits to a marker; if not specified will return first hit only")
    parser.add_argument('--checkType', choices = ["NORMAL", "UPDATE", "FINAL"], default="NORMAL")
    parser.add_argument('--test', help="test run, supply # of lines to read from input file", type=int)
    parser.add_argument('--logAfter', type=int, default=500000)
    parser.add_argument('--maxConnections', type=int, default=10, help="maximum number of database connections")
                        
    
    args = parser.parse_args()
    args.connectionString = AsyncDatabase.connection_string_from_config(gusConfigFile=args.gusConfigFile, url=False)

    errors = None
    mCount = 0
    umCount = 0
    ierrors = None
    icounts = None

    try:
        args = initialize()
        input = parse_input_file()
        indelsFound = len(input['indels']) > 0
        loop = asyncio.get_event_loop()

        LOGGER.info("Processing SNVs/MNVs/short INDELs: n = " + str(len(input['variants'])))
        result = loop.run_until_complete(run(input['header'], input['variants'], 
                                            args.chunkSize, maxConnections=args.maxConnections, append=False))
        errors = result['errors']
        mCount += result['count']
        
        # running through unmapped again w/normalization check
        umCount = len(result['unmapped'])
        if umCount > 0:
            LOGGER.info("Normalizing and remapping unmapped short INDELs: n = " + str(umCount))
            result = loop.run_until_complete(run(input['header'], result['unmapped'], NORMALIZE_CHUNK_SIZE, 
                checkNormalizedAlleles=True, append=True))
            errors = errors + result['errors']
            mCount += result['count']
            unmapped = result['unmapped']
        
        if indelsFound:
            LOGGER.info("Processing INDELS: n = " + str(len(input['indels'])))
            result = loop.run_until_complete(run(input['header'], input['indels'], args.chunkSize,
                maxConnections=args.maxConnections, 
                checkAltVariants=not args.keepIndelDirection, append=True))
            errors = errors + result['errors']
            mCount += result['count']
            
            # running through unmapped again w/normalization check
            umCount = len(result['unmapped'])
            if umCount > 0:
                LOGGER.info("Normalizing and remapping unmapped INDELs: n = " + str(umCount))
                result = loop.run_until_complete(run(input['header'], input['indels'], NORMALIZE_CHUNK_SIZE,
                    checkAltVariants=not args.keepIndelDirection, checkNormalizedAlleles=True, append=True))
                errors = errors + result['errors']
                mCount += result['count']
                unmapped = unmapped + result['unmapped']
                
        umCount = len(unmapped)
        if umCount > 0:
            write_unmapped_variants(input['header'], unmapped)

        LOGGER.info("Mapped " + str(mCount) + " variants.")    
        LOGGER.info("Unable to map " + str(umCount) + " variants.")    
        LOGGER.info("Skipped " + str(input['skipped']) + " invalid variants.")      
            
        LOGGER.info("SUCCESS")
        
    except Exception as err:
        LOGGER.critical(str(err), stack_info=True, exc_info=True)
        
    finally:
        if errors is not None:
            if len(errors) > 0: 
                LOGGER.info("Error mapping " + str(len(errors)) + " variants.")      
                for e in errors:
                    LOGGER.error("Unable to map variant: " +  e['error'] 
                        + "; variant = " + xstr(e['variant']) + "; row =  " + xstr(e['input']))
                if len(ierrors) > 0: 
                    LOGGER.info("Error mapping " + str(len(ierrors)) + " INDELs.")      
                    for e in ierrors:
                        LOGGER.error("Unable to map INDEL: " +  e['error'] 
                            + "; variant = " + xstr(e['variant']) + "; row =  " + xstr(e['input']))
                LOGGER.info("FAIL")