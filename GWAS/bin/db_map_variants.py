#!/usr/bin/env python3

import logging
import json
import argparse
import asyncio

from typing import List
from os import getcwd, path, remove as delete_file
from sys import stderr
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

BULK_LOOKUP_SQL = "SELECT * FROM map_variants($1, $2, $3, False) AS mappings"; 
# $1 - comma separated string list of variants
# $2 - firstHitOnly
# $3 - checkAltVariants
# $4 (False) - checkNormalizedAlleles

INPUT_FIELDS = qw('chr bp allele1 allele2 marker metaseq_id freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json mapped_variant bin_index')

class LookupOptions(BaseModel):
    firstHitOnly: bool
    checkAltVariants: bool
    chunkSize: int
    maxConnections: int
    logAfter: int 
    
    def update(self, data: dict):
        """
        update property values from a dictionary
        adapted from https://github.com/pydantic/pydantic/discussions/3139#discussioncomment-4797649

        TODO: abstract out custom BaseModel class with this functionality

        Args:
            data (dict): key-value pairs indicating values to be updated

        Returns:
            updated class object
        """
        update = self.model_dump()
        update.update(data)
        for k,v in self.model_validate(update).model_dump(exclude_defaults=True).items():
            setattr(self, k, v)
        return self
    
def sort_file(fileName: str):
    sortedFileName = fileName + "-sorted.tmp"
    LOGGER.info("Sorting " + fileName)
    cmd = "(head -n 1 " + fileName + " && tail -n +2 " + fileName + " | sort -T " + args.outputDir + " -V -k1,1 -k2,2) > " + sortedFileName
    execute_cmd(cmd, shell=True)
    execute_cmd("mv " + sortedFileName + " " + fileName, shell=True)
    

def write_unmapped_variants(variants: list):
    """
    write unmapped variants to a VCF file

    Args:
        variants (list): variant:row pairs
    """
    vcfHeader = qw('#CHROM POS ID REF ALT QUAL FILTER INFO', returnTuple=False)
    with open(args.unmappedFile, 'w') as fh:
        print('\t'.join(vcfHeader), file=fh)
        for item in variants:
            variant = list(item.keys())[0]
            chrm, pos, ref, alt = variant.split(':')
            values = [chrm, pos, variant, ref, alt, '.', '.', '.']
            print('\t'.join([xstr(v) for v in values]), file = fh)   
            if args.debug and args.verbose:
                LOGGER.debug("Unmapped Variant: " + xstr({'variant': variant, 'row': item[variant]}))


def check_file(extension: str, fileType:str, suffix:str = ''):    
    """
    check to see if file already exists

    Args:
        extension (str): file extension
        fileType (str): type of file (e.g., log, skip, etc)
        suffix (str, optional): suffix to attach to file name (e.g., for testing). Defaults to ''.

    Returns:
        verified file path
        
    Raises:
        error if file exists and overwrite flag not provided
    """
    baseName = path.basename(args.inputFile)
    filePath = path.join(args.outputDir, baseName + suffix + '.' + extension)
    LOGGER.info(fileType + ": " + filePath)
    if verify_path(filePath):
        if not args.overwrite:
            raise OSError(fileType + " already exists; to overwrite, run with `--overwrite` flag")
        else:
            LOGGER.warning(fileType + " already exists; OVERWRITING")
    return filePath


def standardize_id(value: str):
    """
    standardize metaseq like identifiers

    Args:
        value (str): variant positional and allelic identifier

    Returns:
        standardized value
    """
    return value if value is None \
        else value.replace('_', ':').replace('/', ':').replace('chr', '')
    

def mapping_to_string(value: dict):
    """
    to_string method for a mapping; catches NULLs

    Args:
        value (dict): mapping

    Returns:
        string value of the mapping
    """
    if value is None:
        return "NULL"
    if isinstance(value, str) and value.lower() == "null":
        return "NULL"
    return json.dumps(value)


def build_variant_id(row):
    """
    parse row from input file & generate variant ID

    Args:
        row (CSV dict reader row): row from input file

    Raises:
        ValueError: raised when positional information is incomplete, 
            not mapping thru marker, and failOnInvalidVariant flag is True

    Returns:
        str: variant id
    """
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
            # not an SNV / MNV and len(ref) || len(alt) > expected length
            # e.g., 2  - allows users to specify that AC:T or CG:A will be treated as SNV in lookups
            # so they won't be normalized (unless unmapped) & the process will run faster
            isIndel = len(r) != len(a) and (len(r) > args.indelLength or len(a) > args.indelLength)
    
    # if both alleles are unknown, drop alleles and just map against position
    variantId = regex_replace(':N:N', '', variantId) 
    return variantId, isIndel


async def db_lookup(lookups: list, semaphore: asyncio.Semaphore, flags: LookupOptions):
    """
    run the database lookups

    Args:
        lookups (list): variant:row pairs
        semaphore (asyncio.Semaphore): for limiting number of async calls
        flags (LookupOptions): lookup flags

    Returns:
        the mappings
    """
    sql = None
    parameters = None
    async with semaphore:
        variants = [k for i in [list(d) for d in lookups] for k in i]
        sql = BULK_LOOKUP_SQL
        parameters = [','.join(variants), flags.firstHitOnly, flags.checkAltVariants]
            
        try:
            annotator = AsyncDatabase(connectionString=args.connectionString)
            await annotator.connect()
            connection = annotator.connection()
            mappings = await connection.fetchval(sql, *parameters, column=0)       
            return {"lookups": lookups, "mappings": mappings }
        
        except Exception as err:
            raise err

        finally:
            await annotator.close()
            

async def async_db_mapping(header:list, lookups:list, options:LookupOptions, append=False):
    """
    chunk the variant list, make the async lookups and process results

    Args:
        header (list): header fields
        lookups (list): variant:row pairs
        options (LookupOptions): flags and options for async lookups
        append (bool, optional): append results to existing files or overwrite. Defaults to False.

    Returns:
        dict: count of processed, unmapped variants, and list of errors
    """

    LOGGER.info("Starting parallel processing; max number workers = " 
        + str(options.maxConnections) 
        + "; chunk size = " + str(options.chunkSize) 
        + "; logging after = " + str(options.logAfter))
    
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
                            
        semaphore = asyncio.Semaphore(options.maxConnections)
        chunks = chunker(list(lookups), size=options.chunkSize, returnIterator=False)
        tasks = [asyncio.create_task(db_lookup(c, semaphore, options)) for c in chunks]
        
        for task in asyncio.as_completed(tasks):
            try:
                result = await task
                    
            except Exception as err:
                LOGGER.critical("DB Lookup Error:" + str(err), stack_info=True, exc_info=True)
                
            mappings = result['mappings']
            variantSet = result['lookups']

            for item in variantSet:
                count = count + 1
                variant = list(item.keys())[0]
                row = list(item.values())[0]
                mappedVariant = mappings[variant]
                if mappedVariant is None:
                    unmapped.append(item)
                    row['db_mapped_variant'] = 'NULL' # placeholder so it can be found & updated later
                    print('\t'.join([ row[field] for field in mappedHeader]), file = mfh)  
                elif 'error' in mappedVariant:
                    print('\t'.join([ row[field] for field in header]), file = efh)   
                    errors.append(mappedVariant)
                else:      
                    row['db_mapped_variant'] = mapping_to_string(mappings[variant])
                    print('\t'.join([ row[field] for field in mappedHeader]), file = mfh)
                    mCount = mCount + 1
                
                if count % options.logAfter == 0:
                    LOGGER.info("Processed " + str(count) + " variants.")
        
                
    LOGGER.info("Processed " + str(count) + " variants.")    
    return {'count': mCount, 'unmapped': unmapped, 'errors': errors}



def run():
    lookupThreshold = args.test if args.test and args.test < 1000000 else 1000000
    
    options = LookupOptions(
        chunkSize = args.chunkSize, 
        maxConnections = args.maxConnections, 
        checkAltVariants = True,
        firstHitOnly = not args.allHits,
        logAfter = args.logAfter
    )
    

    variants = [] # using array in case of multiple rows mapped to same variant
    indels = []
    errors = []
    unmapped = []
    
    skipCount = 0
    mappedCount = 0
    lineCount = 0
    asyncRunCount = 0
    with open(args.inputFile, 'r') as fh, open(args.skipFile, 'w') as sfh:      
        reader = DictReader(fh, delimiter='\t')
        header = reader.fieldnames
        
        print('\t'.join(header), file=sfh)
            
        for row in reader:
            lineCount = lineCount + 1
            variantId, isIndel = build_variant_id(row)
            
            if variantId is None:
                print('\t'.join([row[field] for field in header]), file = sfh)   
                skipCount = skipCount + 1
            else:                   
                if isIndel:
                    # indels will be processed separately to allow
                    # to not checkAltIndels if keepIndelDirection is specified
                    indels.append({variantId: row})
                else:
                    variants.append({variantId: row})
            
            if lineCount % 500000 == 0:
                LOGGER.info("Parsed " + str(lineCount) + " lines.")
            
            if lineCount % lookupThreshold == 0:
                asyncRunCount = asyncRunCount + 1
                LOGGER.info("RUN " + xstr(asyncRunCount) + " - Processing SNVs/MNVs/short INDELs: n = " + str(len(variants)))
                result = asyncio.run(async_db_mapping(header, variants, options, append=False if asyncRunCount == 1 else True))
                errors = result['errors']
                mappedCount = result['count']
                unmapped = result['unmapped']
                variants = []
                
                if args.test and lineCount % args.test == 0:
                    LOGGER.info("DONE reading test lines.")
                    break
        
        if len(indels) > 0:
            LOGGER.info("Processing INDELS: n = " + str(len(indels)))
            
            options.update({'checkAltVariants':not args.keepIndelDirection})
            result = asyncio.run(async_db_mapping(header, indels, options, append=True))
            
            errors = errors + result['errors']
            unmapped = unmapped + result['unmapped']
            mappedCount += result['count']


    LOGGER.info("DONE processing file.")
    if skipCount > 0:
        LOGGER.info("Found " + str(skipCount) + " invalid variants; see: " + args.skipFile)
    else: # remove the skip file if empty
        delete_file(args.skipFile)
        
    umCount = len(unmapped)
    if umCount > 0:
        write_unmapped_variants(unmapped)

    LOGGER.info("Parsed " + str(lineCount) + " lines.")
    LOGGER.info("Mapped " + str(mappedCount) + " variants.")    
    LOGGER.info("Unable to map " + str(umCount) + " variants.")    
    LOGGER.info("Skipped " + str(skipCount) + " invalid variants.")     
    
    return errors 


def initialize():
    """
    validates params/command line args & initializes settings / file names / logger

    Raises:
        ValueError: _description_

    Returns:
        validated params / args
    """
    
    suffix = '' if not args.outputSuffix else '-' + args.outputSuffix
    
    logFileName = path.join(args.outputDir, path.basename(args.inputFile) + suffix + ".log")
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
    
    LOGGER.info("SETTINGS")
            
    if args.maxConnections > 50:
        LOGGER.warning("maxConnections too high, setting to 50")
        args.maxConnections = 50
    LOGGER.info("Max number of threads: " + str(args.maxConnections))
    
    args.connectionString = AsyncDatabase.connection_string_from_config(gusConfigFile=args.gusConfigFile, url=False)

    args.mappedFile = check_file("map", "DB mapped variants file", suffix)
    args.unmappedFile = check_file("unmap.vcf" , "Unmapped DB mapped variants file", suffix)
    args.skipFile = check_file("skip", "Skipped variants file", suffix)
    args.errorFile = check_file("error", "DB mapping error file", suffix)
    
    # create hash of variant_id -> line #   
    numLines = file_line_count(args.inputFile, header=True)
    LOGGER.info("Estimated Lines in Input File: " + str(numLines))
    LOGGER.info("Chunk Size = " + str(args.chunkSize))
    
    if args.test:
        if args.test > numLines:
            raise ValueError("TEST size > # lines in file")
        LOGGER.info("Running in TEST mode; processing: " + str(args.test) + " lines.")
        f, i  = modf(args.test / args.chunkSize)
        LOGGER.info("Estimated paged lookups: " + (str(int(i) + 1) if f > 0 else str(int(i))))
    else:
        f, i = modf(numLines / args.chunkSize)
        LOGGER.info("Estimated paged lookups: " + (str(int(i) + 1) if f > 0 else str(int(i))))
        
    return args


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="", allow_abbrev=False)
    parser.add_argument('--inputFile', help="full path to input file", required=True)
    parser.add_argument('--log2stderr', action="store_true", help="log to stderr instead of a file")
    parser.add_argument('--outputSuffix', help="suffix to append to output files to prevent overwriting; for debug/testing")
    parser.add_argument('--outputDir', default=getcwd(), help="full path to output directory; if not specified will use current working directory")
    parser.add_argument('--gusConfigFile', help="gus config file; defaults to $GUS_HOME/config/gus.config if not specified")
    parser.add_argument('--debug', action='store_true')
    parser.add_argument('--verbose', action='store_true')
    parser.add_argument('--chunkSize', type=int, default=5000)
    parser.add_argument('--indelLength', type=int, default=2, help="length of variant considered to be a 'long' INDEL")
    parser.add_argument('--failOnInvalidVariant', action='store_true', help="fail when invalid variants found, otherwise logs & skips")
    parser.add_argument('--useMarker', action='store_true')
    parser.add_argument('--keepIndelDirection', action='store_true', help="if specified will not check alt allele configurations for INDELs")
    parser.add_argument('--allHits', action='store_true', help="return all hits to a marker; if not specified will return first hit only")
    parser.add_argument('--test', help="test run, supply # of lines to read from input file", type=int)
    parser.add_argument('--logAfter', type=int, default=500000)
    parser.add_argument('--maxConnections', type=int, default=10, help="maximum number of database connections")
    parser.add_argument('--overwrite', action='store_true', help="overwrite existing files")
                        
    args = parser.parse_args()
    errors = []
    try:
        args = initialize()
        
        errors = run()

        LOGGER.info("Sorting mapping files.") 
        sort_file(args.unmappedFile)
        sort_file(args.mappedFile)
        
        if len(errors) > 0: 
            LOGGER.info("Error mapping " + str(len(errors)) + " variants.")      
            for e in errors:
                LOGGER.error("Unable to map variant: " +  e['error'] 
                    + "; variant = " + xstr(e['variant']) + "; row =  " + xstr(e['input']))
            
            LOGGER.info("FAIL")    

        else:
            LOGGER.info("SUCCESS")
        
    except Exception as err:
        LOGGER.critical(str(err), stack_info=True, exc_info=True)
