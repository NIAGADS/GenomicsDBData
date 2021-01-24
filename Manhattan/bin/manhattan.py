#!/usr/bin/env python3.6
""" proof of concept"""

import argparse
import rpy2
import os
from rpy2.robjects.packages import importr
from rpy2.robjects.functions import SignatureTranslatedFunction as stm
from rpy2.robjects.packages import STAP # SignatureTranslatedAnalymousPackage

import warnings # suppress rpy2 warnings
from rpy2.rinterface import RRuntimeWarning# , RUserWarning

from rpy2.robjects import r, pandas2ri
from GenomicsDBData.Manhattan.gwas_track import GWASTrack
from GenomicsDBData.Util.utils import warning

BASIC_MANHATTAN_PLOT_SCRIPT = os.path.join(os.environ['GUS_HOME'], 'lib', 'R', 'Manhattan', 'basic_manhattan.R')
CIRCULAR_MANHATTAN_PLOT_SCRIPT = os.path.join(os.environ['GUS_HOME'], 'lib', 'R', 'Manhattan', 'circular_manhattan.R')
VERTICAL_MANHATTAN_PLOT_SCRIPT = os.path.join(os.environ['GUS_HOME'], 'lib', 'R', 'Manhattan', 'vertical_manhattan.R')


def load_function(scriptFile, functionName):
    ''' load an r function from a .R file'''
    with open(scriptFile, 'r') as fh:
        fileStr = f.read()
        myfunc = STAP(fileStr, functionName)


def plot_circular_manhattan():
    ''' plot circular manhattan '''
    circular = load_function(CIRCULAR_MANHATTAN_PLOT_SCRIPT, "circular")
    
    svgFile = os.path.join(args.outputPath, args.track + "-cmanhattan.svg")
    grdevices.svg(file=svgFile, width=512, height=512)
    circular.manhattan(track.get_data())
    grdevices.devoff()


def plot_vertical_manhattan():
    ''' plot veritical manhattan '''
    vertical = load_function(VERICAL_MANHATTAN_PLOT_SCRIPT, "vertical")
    
    svgFile = os.path.join(args.outputPath, args.track + "-vmanhattan.svg")
    grdevices.svg(file=svgFile, width=512, height=512)
    vertical.manhattan(track.get_data(), track.get_gene_annotation())
    grdevices.devoff()
    

def plot_basic_manhattan():
    ''' plot basic manhattan '''
    basic = load_function(BASIC_MANHATTAN_PLOT_SCRIPT, "basic")
    
    svgFile = os.path.join(args.outputPath, args.track + "-manhattan.svg")
    grdevices.svg(file=svgFile, width=512, height=512)
    basic.manhattan(track.get_data(), main = track.get_title())
    grdevices.devoff()
    

def fetch_data():

    if not args.annotateOnly:
        track.fetch_track_data()
        track.fetch_title()
    

    track.fetch_gene_data()

 

if __name__ == "__main__":

    parser = argparse.ArgumentParser()
    parser.add_argument('-t', '--track', help='track key', required=True)
    parser.add_argument('-p', '--plotType', help='type of manhattan plot to generate', default="all")
    parser.add_argument('-l', '--limit', help='limit number of rows to return')
    parser.add_argument('-o', '--outputPath', help='outputPath', required=True)
    parser.add_argument('-c', '--cap', help='-log 10 pvalue cap (recommend 50)', type=int)
    parser.add_argument('--annotateOnly',  help='annotateOnly?', action='store_true')
    parser.add_argument('--rlib')

    args = parser.parse_args()

    rpy2.robjects.r['options'](warn=-1)
    
    # warnings.filterwarnings("ignore", category=RRuntimeWarning)
    # warnings.filterwarnings("ignore", category=RUserWarning)
    pandas2ri.activate()

    r_base = importr('base')
    r_utils = importr('utils')
    r_grdevices = importr('grDevices')


    track = GWASTrack(args.track)
    track.connect(None)
    if args.limit:
        track.set_limit(args.limit)
    if args.cap:
        track.set_cap(args.cap)
        
    fetch_data()

    if not args.annotateOnly:
        track.get_data().to_csv(args.track + "-track.txt", sep="\t")
        
    track.get_gene_annotation().to_csv(args.track + "-annotation.txt", sep="\t")

    # warning("Starting manhattan")
    # if args.plotType == "basic":
    #     plot_basic_manhattan()
