import logging
import json
import argparse

from csv import DictReader
from enum import Enum
from os import path
from sys import stdout

from niagads.utils.logging import ExitOnExceptionHandler
from niagads.parsers.args import json_type
from niagads.utils.dict import print_dict
from niagads.utils.sys import verify_path, file_line_count
from niagads.utils.reg_ex import regex_replace
from niagads.utils.list import qw, chunker
from niagads.utils.string import eval_null

LOGGER = logging.getLogger(__name__)
ALLOWABLE_MARKER_FLAGS = qw('METASEQ_ID PROBE INDICATES_INDEL REFSNP_ID')

def marker_flag_list(value):
    values = value.split(',')

    if set(values).issubset(set(ALLOWABLE_MARKER_FLAGS)):
        return values
    else: 
        raise argparse.ArgumentTypeError("Invalid choices selected for --markerFlags: " + value)


def validate_field_map(obj):
    1

def validate_probe_args():
    hasProbeField = 'probe' in args.fieldMap or 'PROBE' in args.markerFlags
    hasProbeAnnotation = args.probeAnnotationFile is not None

 

def build_variant_id(row):
    variantId = None
    marker = eval_null(row['marker'])
    metaseqId = eval_null(row['metaseq_id'])
    if args.useMarker:     
        if marker.count(':') == 3:
            variantId = marker
        else:
            variantId = ':'.join(marker, row['allele1'], row['allele2']) 
    else:        
        if metaseqId is None:
            chrom = eval_null(row['chr'])
            if chrom is None:       
                variantId = ':'.join(marker, row['allele1', row['allele2']])
            else:
                variantId = ':'.join(chrom, row['bp'], row['allele1'], row['allele2'])
        else:
            variantId = metaseqId
    
    # if both alleles are unknown, drop alleles and just map against position
    variantId = regex_replace(':N:N', variantId) 
    return variantId

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="generate a standardized input file for gwas summary statistics", allow_abbrev=False)
    parser.add_argument('-i', '--inputFile', help="full path to input file", required=True)
    parser.add_argument('--customChrMap', type=json_type, 
                        help="custom chromosome mapping in JSON format, e.g., " + print_dict({"25": "X"}))
    parser.add_argument('--markerFlags', choices=ALLOWABLE_MARKER_FLAGS, type=marker_flag_list,
                        help="marker flags")
    parser.add_argument('--fieldMap', help="field mappings in JSON format", type=json_type, action=validate_field_map)
    parser.add_argument('--chromosome', help="column containing chromosome")
    parser.add_argument('--position', help="column containing position")
    parser.add_argument('--freq', help="column containing frequency value")
    parser.add_argument('--refAllele', help="column containing reference allele")
    parser.add_argument('--altAllele', help="column containing alternative allele")
    parser.add_argument('--testAllele', help="column containing test allele")
    parser.add_argument('--marker', help="column containing variant ID or marker name")
    parser.add_argument('--pvalue', help="column containing pvalue")
    parser.add_argument('--restrictedStats', type=json_type,
                        help='json object of key value pairs for additional scores/annotations that have restricted access')
    parser.add_argument('--probeAnnotationFile', help="full path to probe annotation file")
    parser.add_argument('--genomeWideSignificanceThreshold', type=float, default=5e-8,
                        help="threshold for flagging result has having genome wide signficiance; provide in scientific notation")
    parser.add_argument('--useMarker', action='store_true')
    parser.add_argument('--debug', action='store_true')
    
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