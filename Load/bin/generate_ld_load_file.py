#!/usr/bin/env python
#pylint: disable=invalid-name

'''
Generates load file from PLINK LD output
'''

from __future__ import with_statement
from __future__ import print_function

import argparse

import os.path as path
from os import listdir

import gzip
import mmap
import datetime
import csv

import multiprocessing
from concurrent.futures import ProcessPoolExecutor

from GenomicsDBData.Util.utils import qw, xstr, warning, die, verify_path
from GenomicsDBData.Util.postgres_dbi import Database


def generate_load_file(fileName):
    ''' look up variants and generate output file '''

    outputFile = path.join(args.dir, 'preprocess_' + fileName + '.txt')
    logFile = outputFile + '.log'

    if args.overwrite:
        if verify_path(outputFile):
            warning("Output file:", outputFile, "already exists; skipping")
            return

    inputFile = path.join(args.dir, fileName)
   

    database = Database(args.gusConfigFile)
    database.connect()

    chrm = None
    count = 0
    lineCount = 0
    mappedVariants = {}

    with database.cursor("RealDictCursor") as cursor, \
        open(outputFile, 'w') as of, open(logFile, 'w') as lfh, \
        open(inputFile, 'r') as fhandle:

        mappedFile = mmap.mmap(fhandle.fileno(), 0, prot=mmap.PROT_READ) # put file in swap
        with gzip.GzipFile(mode='r', fileobj=mappedFile) as gfh:
            warning("Parsing", inputFile, file=lfh, flush=True)
            fields = {k: v for v, k in enumerate(gfh.readline().split())}
            if args.debug:
                warning("fields", fields)

            for line in gfh:
                line = line.rstrip()
                row = line.split()
                lineCount = lineCount + 1

                if args.debug:
                    warning("row", row)

                if lineCount == 1:
                    chrm = row[fields['CHR_A']]
                    if chrm == 'MT': chrm = 'M'
                    if chrm == '26': chrm = 'M'
                    if chrm == '23': chrm = 'X'
                    chrm = 'chr' + xstr(chrm)

                if args.debug:
                    warning("chrm", chrm)

                bpA =  row[fields['BP_A']]
                bpB =  row[fields['BP_B']]

                variantA = get_variant_id(cursor, mappedVariants, row[fields['SNP_A']], chrm, bpA)

                if not variantA:
                    continue

                variantB = get_variant_id(cursor, mappedVariants, row[fields['SNP_B']], chrm, bpB)

                if not variantB:
                    continue

                if args.debug:
                    warning("variants:", variantA, variantB)

                mafA = row[fields['MAF_A']]
                mafB = row[fields['MAF_B']]

                mafs = '{' + xstr(mafA) + ',' + xstr(mafB) + '}'
                distance = int(bpB) - int(bpA)
                locations = '{' + xstr(bpA) + ',' + xstr(bpB) + '}'
                rSquared = row[fields['R2']]
                dPrime = row[fields['DP']]

                for va in variantA:
                    for vb in variantB:
                        variants = '{' + xstr(va) +',' + xstr(vb) + '}'
                        print('|'.join((chrm, variants, locations, mafs, xstr(distance), xstr(rSquared), xstr(dPrime))), file=of)
                        of.flush()
                        count = count + 1

                if count % 50000 == 0:
                    warning("WROTE", count, "records; PROCESSED", lineCount, file=lfh, flush=True)
                if args.debug and lineCount == 500:
                    die("DEBUG - DONE")

        warning("DONE -- Wrote", count, "/ Processed", lineCount, file=lfh, flush=True)

    database.close()


def get_variant_id_by_position(cursor, chrm, pos):
    ''' fetch variant id given chr:pos '''
    if args.debug: 
        warning("get_variant_id_by_pos", chrm, pos)
    cursor.execute(POSITION_SQL, (chrm, pos))
    variants = []
    for record in cursor:
        variants.append(record['ref_snp_id'])
    if not variants:
        return None
    return variants


def get_variant_id(cursor, mappedVariants, vId, chrm, pos):
    ''' fetch variant id given rsId'''
    if args.debug: 
        warning("get_variant_id", vId, chrm, pos)

    variants = None
    if len(mappedVariants) > 10000: # so that lookups don't become too slow
        mappedVariants.clear()

    if vId not in mappedVariants:        
        if 'rs' in vId:
            cursor.execute(RS_SQL, (vId, chrm)) # checks merged variants
            variants = []
            for record in cursor:
                variants.append(record['ref_snp_id'])

            if not variants:
                variants = get_variant_id_by_position(cursor, chrm, pos)

        else:
            variants = get_variant_id_by_position(cursor, chrm, pos)

        mappedVariants[vId] = variants
    return mappedVariants[vId]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="generate LD load file")
    parser.add_argument('-d', '--dir', help="directory containing input files", required=True)
    parser.add_argument('-c', '--chr', help="just process the selected chromosome (one of 1-22, X,Y, MT")
    parser.add_argument('--gusConfigFile')
    parser.add_argument('--debug', action='store_true')
    parser.add_argument('--overwrite', help="overwrite existing files?", action='store_true')
    args = parser.parse_args()
 
    RS_SQL = "SELECT ref_snp_id FROM find_variant_by_refsnp(%s, %s, true)"
    if args.debug:
        warning("DEBUG ON")

    # find only SNVs by position
    POSITION_SQL = """SELECT DISTINCT ref_snp_id FROM find_variant_by_position(%s, %s)
WHERE length(split_part(metaseq_id, ':', 3)) = 1 AND length(split_part(metaseq_id, ':', 4)) = 1"""

    if args.chr:
        filename = 'chr' + xstr(args.chr) + '.ld.gz'
        warning("Processing:", filename)
        generate_load_file(filename)

    else:
        files = [f for f in listdir(args.dir) if f.endswith('.ld.gz')]

        with ProcessPoolExecutor(max_workers=10) as executor:
            for fn in files:
                warning("Create and start thread for", fn)
                executor.submit(generate_load_file, fn)
