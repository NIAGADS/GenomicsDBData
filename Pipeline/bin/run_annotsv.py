#!/usr/bin/env python3
# pylint: disable=invalid-name
# pylint: disable=multiple-statements

"""
call loading pipeline to run annotsv
"""

import re
import argparse
from concurrent.futures import ThreadPoolExecutor
from glob import glob
from os import environ, path

from GenomicsDBData.Util.utils import execute_cmd, warning, xstr, create_dir


def get_environ(var):
    try:
        return environ[var]
    except:
        raise ValueError(f"Must set `{var}` environmental variable")


def split_file(fileName):
    snpEffPath = get_environ("SNPEFF_HOME")
    # fmt:off
    cmd = ["java", "-jar",
           f"{snpEffPath}/SnpSift.jar", "split", 
           "-l", "5000",
           fileName
        ]
    # fmt:on
    cmd = " ".join([xstr(c) for c in cmd])
    execute_cmd(cmd, None, printCmdOnly=args.printCmdOnly, shell=True)
    pattern = fileName.replace(".vcf", ".*.vcf")
    files = glob(pattern)
    return files


def run(fileName):

    cacheDir = get_environ("ANNOTSV_CACHE")
    chrm = re.search(r"(chr\d+)", fileName).group(1)
    outputDir = create_dir(path.join(args.inputDir, chrm))

    files = split_file(fileName)
    for f in files:
        print(f"Processing {chrm}: {f}")

        # fmt:off
        cmd = [
            "AnnotSV",
            "-SVinputFile", f,
            "-annotationsDir", cacheDir, 
            # "-annotationMode", "full",
            "-outputDir", outputDir,
            "-tx", "ENSEMBL",
            "-overwrite", 1,
            "-SVminSize", 40
        ]
        # fmt:on
        cmd = " ".join([xstr(c) for c in cmd])
        execute_cmd(cmd, None, printCmdOnly=args.printCmdOnly, shell=True)

    # clean up
    for f in files:
        cmd = f"rm {f}"
        execute_cmd(cmd, None, printCmdOnly=args.printCmdOnly, shell=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="run AnnotSV in parallel")
    parser.add_argument("--maxWorkers", help="number of threads", type=int, default=5)
    parser.add_argument(
        "--printCmdOnly", help="print command only as test", action="store_true"
    )
    parser.add_argument("--fileName")
    parser.add_argument("--inputDir")
    parser.add_argument("--pattern")

    args = parser.parse_args()

    if args.fileName:
        run(args.fileName)
    else:

        files = glob(args.inputDir + "/" + args.pattern)
        with ThreadPoolExecutor(max_workers=args.maxWorkers) as executor:
            for f in files:
                warning("Create and start thread for: " + f)
                executor.submit(run, f)
