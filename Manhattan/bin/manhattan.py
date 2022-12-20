#!/usr/bin/env python3
""" proof of concept"""

import argparse
import os

from GenomicsDBData.Manhattan.gwas_track import GWASTrack
from GenomicsDBData.Util.utils import warning, create_dir, execute_cmd

def fetch_data():
    if not args.annotateOnly:
        track.fetch_track_data()
        track.fetch_title()
        track.get_data().to_csv(os.path.join(args.outputPath, trackName + "-track.txt"), sep="\t")
        
    track.fetch_gene_data()
    track.get_gene_annotation().to_csv(os.path.join(args.outputPath, trackName + "-annotation.txt"), sep="\t")

if __name__ == "__main__":

    parser = argparse.ArgumentParser()
    parser.add_argument('-t', '--tracks', help='track key/may be comma separated list', required=True)
    parser.add_argument('--generatePlots', help='generate plots', action='store_true')
    parser.add_argument('-l', '--limit', help='limit number of rows to return for test')
    parser.add_argument('-o', '--outputPath', help='outputPath', required=True)
    parser.add_argument('-c', '--cap', default=50, help='-log 10 pvalue cap (recommend 50)', type=int)
    parser.add_argument('--annotateOnly',  help='annotateOnly?', action='store_true')
    parser.add_argument('--fetchData',  help='fetch data? use --annotateOnly flag to only fetch annotation', action='store_true')

    args = parser.parse_args()

    create_dir(args.outputPath)

    tracks = args.tracks.split(',')
    for trackName in tracks:
        track = GWASTrack(trackName)
        track.connect(None)
        if args.limit:
            track.set_limit(args.limit)
        if args.cap:
            track.set_cap(args.cap)

        if args.fetchData:
            fetch_data()
    
        if args.generatePlots:
            create_dir(os.path.join(args.outputPath, "png"))
            create_dir(os.path.join(args.outputPath, "pdf"))
            cmd = ["generateManhattanPlots.R", trackName, args.outputPath, str(args.cap)]
            execute_cmd(cmd, verbose=True)
