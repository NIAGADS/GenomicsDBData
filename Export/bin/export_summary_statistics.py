#!/usr/bin/env python3
""" export summary statistics for AI/ML gold standard"""

import argparse
import os
from csv import QUOTE_NONE

from GenomicsDBData.Manhattan.gwas_track import GWASTrack
from GenomicsDBData.Util.utils import warning, create_dir, execute_cmd, print_dict
    
if __name__ == "__main__":

    parser = argparse.ArgumentParser()
    parser.add_argument('-t', '--track', help='comma separated list of one or more tracks or an accession if fetching metadata', required=True)
    parser.add_argument('-l', '--limit', help='limit number of rows to return for test')
    parser.add_argument('-a', '--accession', help='accession number; if fetching metadata only, set track to `None`', required=True)
    parser.add_argument('-o', '--outputPath', help='outputPath', required=True)
    parser.add_argument('--bedFile', help='bed output', action='store_true')
    # parser.add_argument('--inclRestricted', action='store_true', help='for BED output, include restricted stats')
    parser.add_argument('--metadataOnly',  help='fetch metadata? (only) --track should equal `None`', action='store_true')

    args = parser.parse_args()


    outputPath = os.path.join(args.outputPath, args.accession) if not args.bedFile \
        else args.outputPath
    create_dir(outputPath)
    

    warning("Fetching metadata for", args.accession, flush=True)
    track = GWASTrack(args.accession)
    track.connect(None)
    if args.limit:
        track.set_limit(args.limit)
    track.fetch_metadata()
    with open(os.path.join(outputPath, args.accession + ".json"), 'w') as fh:
        print(print_dict(track.get_metadata(), pretty=True), file=fh)
        
    if not args.metadataOnly and args.track != 'None':
        tracks = args.track.split(',')
        for trackId in tracks:
            files = []
            warning("Fetching summary statistics for:", trackId)
            track = GWASTrack(trackId)
            track.connect(None)
            if args.limit:
                track.set_limit(args.limit)
            
            if not args.bedFile:
                track.fetch_public_sum_stats()
                fileName = os.path.join(outputPath, trackId + ".tsv")
                track.get_data().to_csv(fileName, sep="\t", index=False, quoting=QUOTE_NONE)
                files.append(fileName)
            else:
                track.fetch_bed_sum_stats(inclRestricted=True)
                
                fileName = os.path.join(outputPath, f'{trackId}-full.bed' )
                track.get_data().to_csv(fileName, sep="\t", index=False, quoting=QUOTE_NONE)
                files.append(fileName)
                
                fileName = os.path.join(outputPath, f'{trackId}.bed')
                track.get_data().to_csv(fileName, sep="\t", index=False,
                    quoting=QUOTE_NONE, columns=['#chrom', 'chromStart', 'chromEnd', 'name', 'score', 'info'])
                files.append(fileName)

            for fn in files:
                warning("Sorting", fn)      
                cmd = "(head -n 1 " + fn + " && tail -n +2 " + fn  \
                    + " | sort -T " + outputPath + " -V -k1,1 -k2,2) > " + fn + ".sorted"          
                execute_cmd([cmd], shell=True)

                warning("Compressing sorted", fn)
                execute_cmd(["bgzip", fn + ".sorted"])
                execute_cmd(["mv", fn + ".sorted.gz", fn + ".gz"])
                
                warning("Indexing", fn)
                execute_cmd(["tabix", "-S", "1", "-s", "1", "-e", "2", "-b", "2", "-f", fn + ".gz"])

                warning("Cleaning up (removing temp files)")
                execute_cmd(["rm", fn])