#!/usr/bin/env python3
# pylint: disable=invalid-name

'''
patch_display_attributes
'''

import argparse
import os.path as path

from random import shuffle
from sys import stdout
from concurrent.futures import ProcessPoolExecutor, as_completed
from psycopg2 import DatabaseError

from GenomicsDBData.Util.utils import xstr, warning, die, print_dict, print_args
from GenomicsDBData.Util.postgres_dbi import Database, raise_pg_exception

from AnnotatedVDB.Util.enums import HumanChromosome as Human
from AnnotatedVDB.Util.variant_annotator import VariantAnnotator


SELECT_SQL = """SELECT record_primary_key, metaseq_id, display_attributes 
FROM AnnotatedVDB.Variant 
WHERE chromosome = %s
"""


def update_annotation(chromosome):
    # resume = args.resumeAfter is None # false if need to skip lines
    # if not resume:
    #    warning(("--resumeAfter flag specified; Finding skip until point", args.resumeAfter), prefix="INFO")
    #    loader.set_resume_after_variant(args.resumeAfter)
    

    chrmStr = chromosome
    cname = 'select'

    if chromosome is not None:
        chrmStr = chromosome if 'chr' in xstr(
            chromosome) else 'chr' + xstr(chromosome)
        cname += '_' + chrmStr

    logFile = path.join(args.outputFilePath, str(chromosome) + ".log")
    outFile = path.join(args.outputFilePath, str(chromosome) + ".txt")

    database = Database(args.gusConfigFile)
    database.connect()


    with database.named_cursor(cname, cursorFactory="RealDictCursor") as selectCursor, \
        open(logFile, 'w') as lfh, open(outFile, 'w') as ofh:
            
        warning('Generating updated annotation for chr' + xstr(chromosome), prefix="INFO", file=lfh, flush=True)

        selectCursor.itersize = 500000  # args.commitAfter
        recordCount = 0
        updateCount = 0

        print("variant", "display_attributes", sep="\t", file=ofh)

        warning("Executing query: " + SELECT_SQL.replace('%s', "'" + chrmStr + "'"), prefix="DEBUG", file=lfh, flush=True)
        selectCursor.execute(SELECT_SQL, [chrmStr])
        for record in selectCursor:
            #if args.debug:
            #    warning(record, prefix="DEBUG", file=lfh, flush=True)

            
            displayAttributes = record['display_attributes']
            vc = displayAttributes['variant_class_abbrev']
            if vc not in ['SNV', 'MNV']:
                metaseqId = record['metaseq_id']
                chrm, pos, ref, alt = metaseqId.split(':')
                
                if len(ref) > 50 or len(alt) > 50:
                    continue
                
                annotator = VariantAnnotator(ref, alt, chrm, int(pos))
                nref, nalt = annotator.get_normalized_alleles(True)
                nMetaseqId = ':'.join((chrm, pos, nref, nalt))
                if nMetaseqId != metaseqId:
                    if args.debug:
                        warning(metaseqId, nMetaseqId, prefix="DEBUG", file=lfh, flush=True)
                    displayAttributes.update({'normalized_metaseq_id': ':'.join((chrm, pos, nref, nalt))})
                    print(record['record_primary_key'], print_dict(displayAttributes, pretty=False), sep="\t", file=ofh)
                    
            
            recordCount = recordCount + 1
            if recordCount % 100000 == 0:
                warning("Parsed", recordCount, "records", prefix="INFO", file=lfh, flush=True)

                
if __name__ == "__main__":
    parser = argparse.ArgumentParser(allow_abbrev=False,  # otherwise it can substitute --chr for --chromosomeMap
                                     description='load AnnotatedDB from JSON output of VEP against dbSNP, specify either a file or one or more chromosomes')
    parser.add_argument('--chr')
    parser.add_argument('--maxWorkers', default=5, type=int)
    parser.add_argument('--gusConfigFile',
                        help="full path to gus config file, else assumes $GUS_HOME/config/gus.config")
    parser.add_argument('--outputFilePath', required=True,
                        help="full path to external AnnotatedVDB gus config file, else assumes")
    parser.add_argument('--verbose', action='store_true')
    parser.add_argument('--debug',  action='store_true',
                        help="log database copy time / may print development debug statements")
    args = parser.parse_args()

    chrList = args.chr.split(',') if not args.chr.startswith('all') \
        else [c.value for c in Human]
        
    shuffle(chrList) # so not all large chr are done first

    if len(chrList) == 1:
        update_annotation(chrList[0])
    else:
        with ProcessPoolExecutor(args.maxWorkers) as executor:
            for c in chrList:
                #warning(xstr(c))
                executor.submit(update_annotation,chromosome=c)

