#!/usr/bin/env python3
""" export summary statistics for AI/ML gold standard"""

import argparse
import os

from GenomicsDBData.Manhattan.gwas_track import GWASTrack
from GenomicsDBData.Util.utils import warning, create_dir, execute_cmd, print_dict
    
if __name__ == "__main__":

    parser = argparse.ArgumentParser()
    parser.add_argument('-t', '--track', help='comma separated list of one or more tracks or an accession if fetching metadaa', required=True)
    parser.add_argument('-l', '--limit', help='limit number of rows to return for test')
    parser.add_argument('-o', '--outputPath', help='outputPath', required=True)
    parser.add_argument('--metadata',  help='fetch metadata? (only) --track should specify the parent accession', action='store_true')

    args = parser.parse_args()

    create_dir(args.outputPath)
    
    if args.metadata:
        track = GWASTrack(args.track)
        track.connect(None)
        if args.limit:
            track.set_limit(args.limit)
        track.fetch_metadata()
        with open(os.path.join(args.outputPath, args.track + "-metadata.json"), 'w') as fh:
            print(print_dict(track.get_metadata(), pretty=True), file=fh)
        
    else:
        tracks = args.tracks.split(',')
        for trackName in tracks:
            track = GWASTrack(trackName)
            track.connect(None)
            if args.limit:
                track.set_limit(args.limit)
            track.fetch_public_sum_stats()
            track.get_data().to_csv(os.path.join(args.outputPath, trackName + ".tsv"), sep="\t")
