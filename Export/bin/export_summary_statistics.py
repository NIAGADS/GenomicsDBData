#!/usr/bin/env python3
""" export summary statistics for AI/ML gold standard"""

import argparse
import os

from GenomicsDBData.Manhattan.gwas_track import GWASTrack
from GenomicsDBData.Util.utils import warning, create_dir, execute_cmd, print_dict
    
if __name__ == "__main__":

    parser = argparse.ArgumentParser()
    parser.add_argument('-t', '--track', help='comma separated list of one or more tracks or an accession if fetching metadata', required=True)
    parser.add_argument('-l', '--limit', help='limit number of rows to return for test')
    parser.add_argument('-a', '--accession', help='accession number; if fetching metadata only, set track to `None`', required=True)
    parser.add_argument('-o', '--outputPath', help='outputPath', required=True)
    parser.add_argument('--metadataOnly',  help='fetch metadata? (only) --track should equal `None`', action='store_true')

    args = parser.parse_args()

    outputPath = os.path.join(args.outputPath, args.accession)
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
            warning("Fetching summary statistics for:", trackId)
            track = GWASTrack(trackId)
            track.connect(None)
            if args.limit:
                track.set_limit(args.limit)
            track.fetch_public_sum_stats()
            fileName = os.path.join(outputPath, trackId + ".tsv")
            track.get_data().to_csv(fileName, sep="\t", index=False)

            warning("Sorting", fileName)      
            cmd = "(head -n 1 " + fileName + " && tail -n +2 " + fileName  \
                + " | sort -T " + outputPath + " -V -k1,1 -k2,2) > " + fileName + ".sorted"          
            execute_cmd([cmd], shell=True)

            warning("Compressing sorted", fileName)
            execute_cmd(["bgzip", fileName + ".sorted"])
            execute_cmd(["mv", fileName + ".sorted.gz", fileName + ".gz"])
            
            warning("Indexing", fileName)
            execute_cmd(["tabix", "-S", "1", "-s", "1", "-e", "2", "-b", "2", "-f", fileName + ".gz"])

            warning("Cleaning up (removing temp files)")
            execute_cmd(["rm", fileName])