#!/usr/bin/env python3
""" proof of concept"""

import argparse
import os

from concurrent.futures import ProcessPoolExecutor, as_completed

from GenomicsDBData.Manhattan.gwas_track import GWASTrack
from GenomicsDBData.Util.utils import warning, create_dir, execute_cmd
            
def run(options, trackId):
    accession = trackId.split('_')[0]
    outputPath = os.path.join(options.outputPath, accession)
    create_dir(outputPath)
    warning("Fetching track: ", trackId, "- writing to: ", outputPath)
    
    track = GWASTrack(trackId)
    track.connect(None)
    
    if options.limit:
        track.set_limit(options.limit)
        
    if options.cap:
        track.set_cap(options.cap)

    if options.fetchData:
        fetch_data(trackId, track, outputPath, options.annotateOnly)

    if options.generatePlots:
        warning("Plotting track: ", trackId)
        create_dir(os.path.join(outputPath, "png"))
        create_dir(os.path.join(outputPath, "pdf"))
        cmd = ["generateManhattanPlots.R", trackId, outputPath, str(options.cap), options.plotType]
        execute_cmd(cmd, verbose=True)
        
            
def fetch_data(trackId, track, outputPath, annotateOnly):
    if not annotateOnly:
        track.fetch_track_data()
        track.fetch_title()
        track.get_data().to_csv(os.path.join(outputPath, trackId + "-track.txt"), sep="\t")
        
    track.fetch_gene_data()
    track.get_gene_annotation().to_csv(os.path.join(outputPath, trackId + "-annotation.txt"), sep="\t")


if __name__ == "__main__":

    parser = argparse.ArgumentParser()
    parser.add_argument('-t', '--tracks', help='track key/may be comma separated list;`fromDB` to have the database get the list of tracks', required=True)
    parser.add_argument('--generatePlots', help='generate plots', action='store_true')
    parser.add_argument('-p', '--plotType', help='plot type', default='all', choices=["all", "plotly", "png"])
    parser.add_argument('-l', '--limit', help='limit number of rows to return for test')
    parser.add_argument('-o', '--outputPath', help='outputPath', required=True)
    parser.add_argument('-c', '--cap', default=50, help='-log 10 pvalue cap (recommend 50)', type=int)
    parser.add_argument('--annotateOnly',  help='annotateOnly?', action='store_true')
    parser.add_argument('--maxWorkers', default=5, type=int, help="max parallel workers")
    parser.add_argument('--fetchData',  help='fetch data? use --annotateOnly flag to only fetch annotation', action='store_true')

    args = parser.parse_args()

    create_dir(args.outputPath)

    tracks = args.tracks.split(',')
    
    with ProcessPoolExecutor(args.maxWorkers) as executor:
        futureProcess = {executor.submit(run, args, t) : t for t in tracks} 
        for future in as_completed(futureProcess): # this should allow catching errors
                try:
                    future.result()
                except Exception as err:
                    raise(err)              
