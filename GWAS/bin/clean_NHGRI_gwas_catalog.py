#!/usr/bin/env python3
#pylint: disable=invalid-name
#pylint: disable=no-member
'''
cleans the NHGRI GWAS Catalog dump
'''


import re
import argparse
import os.path as path
import csv
import logging
import json

from collections import OrderedDict
from math import log

from niagads.utils.sys import warning, die
from niagads.utils.string import xstr, is_number, is_non_numeric
from niagads.utils.list import qw
from niagads.utils.dict import print_dict
from niagads.utils.logging import ExitOnCriticalExceptionHandler

LOGGER = logging.getLogger(__name__)


CLEANED_FIELDS = qw('chr bp allele1 allele2 marker metaseq_id freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json')

HEADER_MAP = OrderedDict([
    ('DATE ADDED TO CATALOG', 'date_added_to_catalog'),
    ('PUBMEDID', 'pubmed_id'),
    ('FIRST AUTHOR', 'first_author'),
    ('DATE', 'publication_date'),
    ('JOURNAL', 'journal'),
    ('LINK', 'pubmed_url'),
    ('STUDY', 'study'),
    ('DISEASE/TRAIT', 'trait'),
    ('INITIAL SAMPLE SIZE', 'initial_sample_size'),
    ('REPLICATION SAMPLE SIZE', 'replication_sample_size'),
    ('REGION', 'cytogenic_region'),
    ('CHR_ID', 'chromosome'),
    ('CHR_POS', 'position'),
    ('REPORTED GENE(S)', 'reported_genes'),
    ('MAPPED_GENE', 'mapped_genes'),
    ('UPSTREAM_GENE_ID', 'upstream_gene_id'),
    ('DOWNSTREAM_GENE_ID', 'downstream_gene_id'),
    ('SNP_GENE_IDS', 'snp_gene_ids'),
    ('UPSTREAM_GENE_DISTANCE', 'upstream_gene_distance'),
    ('DOWNSTREAM_GENE_DISTANCE', 'downstream_gene_distance'),
    ('STRONGEST SNP-RISK ALLELE', 'risk_allele'),
    ('SNPS', 'snp'),
    ('MERGED', 'snp_is_merged'),
    ('SNP_ID_CURRENT', 'ref_snp_id'),
    ('CONTEXT', 'most_severe_consequence'),
    ('INTERGENIC', 'snp_is_intergenic'),
    ('RISK ALLELE FREQUENCY', 'frequency'),
    ('P-VALUE', 'p_value'),
    ('PVALUE_MLOG', 'neg_log10_pvalue'),
    ('P-VALUE (TEXT)', 'pvalue_context_qualifier'),
    ('OR or BETA', 'odds_ratio_or_beta'),
    ('95% CI (TEXT)', 'CI95'),
    ('PLATFORM [SNPS PASSING QC]', 'genotyping_platform'),
    ('CNV', 'cnv'),
    ('MAPPED_TRAIT', 'efo_source_id'),
    ('MAPPED_TRAIT_URI', 'efo_uri'),
    ('STUDY ACCESSION', 'study_accession'),
    ('GENOTYPING TECHNOLOGY', 'genotyping_technology')
])


def str2array(value):
    value = value.replace(' ', '').replace(',', ';')
    return value.split(';')

def clean_row(row):
    # these two things cause problems later for postgres json
    row = {key : value.replace('"', '') if value is not None else value for key, value in row.items()}
    row = {key : value.replace('|', '-') if value is not None else value for key, value in row.items()}
    row = {key : value.replace('\\x3b', ';') if value is not None else value for key, value in row.items()}
    row = {key : value.replace('\\h', '|') if value is not None else value for key, value in row.items()}
    return { HEADER_MAP[key]: xstr(value, nullStr='NULL') for key, value in row.items()} # get rid of quotes in json & map fields

def is_null_value(value):
    nulls = ['NR', '', '.', 'NULL']
    return value is None or value in nulls


"""
# sometimes get weird things like ?T or '' but not NULL
alleles = ['N' if (a == '' or '?' in a) else a.upper() for a in alleles] 
alleles = list(dict.fromkeys(alleles)) # remove duplicates


if '?' in alleles:
    alleles = ['N'] # if list of alleles includes a N then the result will be mapped to all alleles anyway, so others do not matter


pos = row["CHR_POS"]
if not pos and ':' in marker:
    pos = marker.split(':')[1]

refAllele = 'N'
if ':' in marker:
    variantInfo = marker.split(':')
    if len(variantInfo) == 4:
        alt = variantInfo[3].upper()
        refAllele = variantInfo[2].upper()


variantTuple = (xstr(chrm), pos, xstr(marker.rstrip()), refAllele)
"""

def clean_snps(snp: str, extractAlleles=False):    
    if not extractAlleles and '-' in snp:
        # missing chrN-pos-? but neglible
        if ':' in snp:
            snpInfo = snp.split(':')
            chrm = snpInfo[0]
            if is_number(chrm) or chrm in ['X', 'Y', 'M', 'MT'] or chrm.startswith('chr'):
                LOGGER.info("Removing allele from SNP marker: %s", snpInfo)
                snpInfo = snp.split('-')
                snp = snpInfo[0]
            else:
                return None
        else:
            return None # invalid
    
    if ' x ' in snp: # snp x snp interaction
        return None
    
    # remove or standardize prefixes
    snp = snp.replace('imm_', '').replace('hg18_', '')
        
    # typo
    snp = snp.replace(':-?',':?')
    snp = snp.replace('"', '')
    snp = snp.replace('--', '-')
    snp = snp.replace('.', ':')
    snp = snp.replace('che', 'chr')
    if snp.startswith('hr'):
        snp = snp.replace('hr', 'chr')
        
    # standardize
    snp = snp.replace('_', ':')
    snp = snp.replace('Chr', 'chr').replace('chr:', '').replace('chr', '').replace('RS', 'rs')
    
    # additional typos
    snp = snp.replace('ch', '')
    
    snps = str2array(snp)
    
    returnVal = []
    for s in snps:
        marker = None
        alleleInfo = None
        
        if extractAlleles:
            s = s.replace(' ', '') # get rid of extra spaces
            if '-' not in s:
                LOGGER.info("No allele specified: %s; adding '-?'", s)      
                s = s + '-?'
            alleleInfo = s.split('-')
            marker = clean_marker(alleleInfo[0])
            
        else:
            marker = clean_marker(s)
            
        if marker is None:
            continue
        
        if extractAlleles:       
            allele = clean_allele(s)
            returnVal.append(allele)
            
        else:
            returnVal.append(marker)
        
    if len(returnVal) == 0:
        return None

    return returnVal


def clean_allele(snp: str):
    alleleInfo = snp.split('-')
    if len(alleleInfo) == 1:
        return '?'
    
    if len(alleleInfo) > 2:
        LOGGER.info("Multiple alleles found, returning '?': %s", alleleInfo)
        return '?'
    
    allele = alleleInfo[1]
    if not any(x in allele for x in ['A', 'C', 'G', 'T', '?']):
        LOGGER.info('Invalid allele found: %s (snp = %s)', xstr(allele), snp)
        return '?'
    
    return allele


def clean_marker(marker: str):
    if any(x in marker.lower() for x in qw('upstream downstream im position b37 POSITION Position > affx snp 1kg d10 y del kgp exm hla')):
        LOGGER.debug("invalid marker: %s", marker)
        return None
    
    if marker.startswith('23:'):
        marker = marker.replace('23:', 'X:')
    if marker.startswith('24:'):
        marker = marker.replace('24:', 'Y')
    
    if args.genomeBuild == 'GRCh38' and marker == '2:179179368916': # one off typo --> 179 is duplicated
        marker = '2:179368916'   
    
    if '*' in marker: 
        LOGGER.debug("invalid %s", marker)
        return None
    
    if marker.startswith('0-'): # e.g. "0-GAAAAAA"
        LOGGER.debug("invalid %s", marker)
        return None
    
    if ':' in marker:
        if marker.startswith(':'):
            marker = marker.replace(':', '', 1)
            
        markerInfo = marker.split(':')
        validChr = True
        if is_number(markerInfo[0]):
            if int(markerInfo[0]) > 22 or int(markerInfo[0]) < 1:
                validChr = False
        elif markerInfo[0] not in ['X', 'Y', 'M', 'MT']:
            validChr = False

        if not validChr:
            LOGGER.warning("Found invalid chromosome: %s (marker = %s)", markerInfo[0], marker)
            return None
        
        if len(markerInfo) == 3:
            if 'I' in markerInfo[2] or 'D' in markerInfo[2]:
                marker = ':'.join(markerInfo[0:2]) # need to catch 4:135285067:I-? or :D-?
    
    if 'rs' not in marker and is_number(marker):
        marker = 'rs' + xstr(marker)
    
    if 'rs' in marker:     # some rsIds have a random alpha-char after them
        match = re.search('(rs\d+)', marker)
        marker = match.group(1)
    
    if not marker.startswith('rs') and ':' not in marker:
        LOGGER.debug("invalid %s", marker)
        return None
    
    return marker


def clean():
    '''
    parse input file and generate load file w/one variant per load file
    extract effect alleles
    '''

    pattern = re.compile(' \(.+\)')

    outputFile = path.join(args.rawFile + '.clean')
        
    lineCount = 0
    skipCount = 0
    
    try: 
        row = None
        with open(outputFile, 'w') as ofh, open(args.rawFile) as fh:
            reader = csv.DictReader(fh, delimiter='\t')
            print('\t'.join(CLEANED_FIELDS), file=ofh)
            for row in reader:
                if args.test is not None:
                    if lineCount != 0 and lineCount % args.test == 0:
                        LOGGER.info("DONE with test")
                        break
                        
                lineCount = lineCount + 1
                row = clean_row(row)
                
                if args.test is not None:
                    LOGGER.debug("Cleaned row: %s", row)
                
                pvalue = None if is_null_value(row['p_value']) \
                    else re.sub(pattern, '', row['p_value']) 
                if pvalue is None:
                    skipCount = skipCount + 1
                    continue
                
                nl10p = None
                if 'E-' in pvalue: 
                    pvalue = pvalue.replace('E-', 'e-')
                    base, power = pvalue.split('e-')
                    if int(power) > 100:
                        nl10p = power
                
                if nl10p is None:
                    nl10p = -1.0 * log(float(pvalue))

                
                frequency = row['frequency']
                if is_null_value(frequency) or ',' in frequency or not frequency.replace('.','').isdigit(): 
                    frequency = 'NULL'
                elif '-' in frequency: # range
                    frequency = 'NULL'
                elif ' ' in frequency:
                    frequency = frequency.split(' ')[0]
                
                frequency = re.sub(pattern, '', frequency)
                
                markers = xstr(row['ref_snp_id'], nullStr='NULL')
                if is_null_value(markers):
                    markers = row['snp'].replace('chr', '')
                    
                cleanMarkers = clean_snps(markers)
                if cleanMarkers is None:
                    LOGGER.info("SKIPPING invalid variant identifier: %s", markers)
                    skipCount = skipCount + 1
                    continue
                
                alleles = clean_snps(row['risk_allele'], extractAlleles=True) 
                
                if len(alleles) != len(cleanMarkers):
                    raise ValueError("number of markers != number of alleles -> %s | %s", cleanMarkers, alleles)
            
                # qw('chr bp allele1 allele2 marker metaseq_id freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json')
                for index, variant in enumerate(cleanMarkers):
                    tAllele = alleles[index]
                    marker = variant
                    if tAllele != '?':
                        if 'rs' in marker or (':' in marker and marker.count(':') == 1): # refsnp or chr:pos only
                            marker = ':'.join((marker, tAllele, 'N')) 
        
                    values = ['NULL', 'NULL', 'NULL', 'NULL', marker, 'NULL', xstr(frequency), xstr(pvalue), xstr(nl10p), xstr(pvalue), 'NULL', tAllele, json.dumps(row)]
                    print('\t'.join(values), file=ofh)
                
        LOGGER.info("Parsed %s lines", lineCount)
        LOGGER.info("Skipped %s lines", skipCount)
    except IOError as err:
        LOGGER.critical("File I/O problem", stack_info=True, exc_info=err)
        raise(err)
    except Exception as err:
        LOGGER.critical("Problem parsing %s", print_dict(row, pretty=True), stack_info=True, exc_info=err)
        raise
    

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="generate load file NHGRI GWAS Catalog tsv file", allow_abbrev=False)
    parser.add_argument('--rawFile', help="file name", required=True)
    parser.add_argument('--test',type=int)
    parser.add_argument('--genomeBuild', default='GRCh38', help="genome build (can match by position only if GRCh38", required=True)
    parser.add_argument('--log2stderr', action='store_true')
    parser.add_argument('--debug', action='store_true')
    args = parser.parse_args()
    
    logFileName = path.join(args.rawFile + '.log')
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
    
    LOGGER.info("Processing %s", args.rawFile)

    clean()

