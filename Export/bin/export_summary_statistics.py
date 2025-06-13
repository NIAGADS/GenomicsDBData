#!/usr/bin/env python3
"""export summary statistics for AI/ML gold standard"""

import argparse
import os
from csv import QUOTE_NONE

from GenomicsDBData.Export.gwas_track import GWASTrack
from GenomicsDBData.Util.utils import create_dir, execute_cmd, print_dict, warning

if __name__ == "__main__":

    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-t",
        "--track",
        help="comma separated list of one or more tracks or an accession if fetching metadata",
        required=True,
    )
    parser.add_argument("-l", "--limit", help="limit number of rows to return for test")
    parser.add_argument(
        "-a",
        "--accession",
        help="accession number; if fetching metadata only, set track to `None`",
        required=True,
    )
    parser.add_argument("-o", "--outputPath", help="outputPath", required=True)
    # parser.add_argument('--inclRestricted', action='store_true', help='for BED output, include restricted stats')
    parser.add_argument(
        "--metadataOnly",
        help="fetch metadata? (only) --track should equal `None`",
        action="store_true",
    )
    parser.add_argument(
        "--fastaRefDir", help="full path to FASTA references", required=True
    )

    args = parser.parse_args()

    outputPath = os.path.join(args.outputPath, args.accession)
    create_dir(outputPath)

    warning("Fetching metadata for", args.accession, flush=True)
    track = GWASTrack(args.accession)
    track.connect(None)
    if args.limit:
        track.set_limit(args.limit)
    track.fetch_metadata()
    with open(os.path.join(outputPath, args.accession + ".json"), "w") as fh:
        print(print_dict(track.get_metadata(), pretty=True), file=fh)

    if not args.metadataOnly and args.track != "None":
        tracks = args.track.split(",")
        for trackId in tracks:
            files = []
            warning("Fetching summary statistics for:", trackId)
            track = GWASTrack(trackId, fastaDir=args.fastaRefDir)
            track.connect(None)
            if args.limit:
                track.set_limit(args.limit)

            files = files + track.export_annotated_sum_stats_as_vcf(dir=outputPath)

            for fn in files:
                warning("Sorting", fn)
                # fmt: off
                cmd = "(cat " + fn  + " | awk '$1 ~ /^#/ {print $0;next} {print $0 | \"sort -T " + outputPath + " -V -k1,1V -k2,2n\"}') > " +  f"{fn}.sorted"  
                # fmt: on
                execute_cmd([cmd], shell=True)

                warning("Compressing sorted", fn)
                execute_cmd(["bgzip", fn + ".sorted"])
                execute_cmd(["mv", fn + ".sorted.gz", fn + ".gz"])

                warning("Indexing", fn)
                # fmt: off
                execute_cmd(["tabix", "-p", "vcf", "-S", "1", "-s", "1", "-e", "2", "-b", "2", "-f", fn + ".gz"])
                # fmt: on

                warning("Cleaning up (removing temp files)")
                execute_cmd(["rm", fn])
