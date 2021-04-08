#!/usr/bin/env Rscript
args = commandArgs(trailingOnly=TRUE)

## test if there is at least one argument: if not, return an error

if (length(args) < 2) {
  stop("Must supply track id (1) and full path the preprocess directory (2)", call.=FALSE)
} 

## track
track  <- args[1]
## preprocess
preprocessDir  <- args[2]

GUS_HOME  <-  Sys.getenv("GUS_HOME")
MANHATTAN_SCRIPT  <- paste(GUS_HOME, "lib/R/Manhattan/circular_manhattan.R", sep="/");
source(MANHATTAN_SCRIPT);

filePrefix  <- paste(preprocessDir, track, sep="/")
pngFilePrefix  <- paste(preprocessDir, "png", track, sep="/")
pdfFilePrefix  <- paste(preprocessDir, "pdf", track, sep="/")

data  <- read.table(paste0(filePrefix, "-track.txt"), sep="\t", header=1, stringsAsFactors = F)
annotation <- read.table(paste0(filePrefix, "-annotation.txt"), sep="\t", header=1, row.names=1, stringsAsFactors=F)

manhattan(data, annotation, toFile=T, fileName=paste0(pngFilePrefix, "-manhattan"), fileType="png", filter=0.5)
cmanhattan(data, NULL, toFile=T, fileName=paste0(pngFilePrefix, "-cmanhattan"), fileType="png", filter=0.5)
# snpDensity(data, toFile=T, fileName=paste0(pngFilePrefix, "-snp-density"), fileType="png")
# qq(data, toFile=T, fileName=paste0(pngFilePrefix, "-qq"), fileType="png")

manhattan(data, annotation, toFile=T, fileName=paste0(pdfFilePrefix, "-manhattan"), fileType="pdf", filter=0.5)
cmanhattan(data, NULL, toFile=T, fileName=paste0(pdfFilePrefix, "-cmanhattan"), fileType="pdf", filter=0.5)
# qq(data, toFile=T, fileName=paste0(pdfFilePrefix, "-qq"), fileType="pdf")
# snpDensity(data, toFile=T, fileName=paste0(pdfFilePrefix, "-snp-density", fileType="pdf")

quit(save="no", status=0)
