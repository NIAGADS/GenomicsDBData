#!/usr/bin/env Rscript

## parse args
args = commandArgs(trailingOnly=TRUE)

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
library(data.table) # for faster read and progress bar

filePrefix  <- paste(preprocessDir, track, sep="/")
pngFilePrefix  <- paste(preprocessDir, "png", track, sep="/")
pdfFilePrefix  <- paste(preprocessDir, "pdf", track, sep="/")

message("Reading data")
data  <- fread(paste0(filePrefix, "-track.txt"), sep="\t", header=T, stringsAsFactors = F, showProgress=T, data.table=F)

message("Reading annotation")
annotation <- fread(paste0(filePrefix, "-annotation.txt"), sep="\t", header=T, stringsAsFactors=F, showProgress=T, data.table=F)
row.names(annotation)  <- annotation$hit # data.tables don't have row.names

## data  <- read.table(paste0(filePrefix, "-track.txt"), sep="\t", header=1, stringsAsFactors = F)
## annotation <- read.table(paste0(filePrefix, "-annotation.txt"), sep="\t", header=1, row.names=1, stringsAsFactors=F)

message("Filtering data")
fdata  <- filterData(data, 0.5)

message("Generating PNGs")
manhattan(fdata, annotation, toFile=T, fileName=paste0(pngFilePrefix, "-annotated-manhattan"), fileType="png")
manhattan(fdata, NULL, toFile=T, fileName=paste0(pngFilePrefix, "-manhattan"), fileType="png")
cmanhattan(fdata, NULL, toFile=T, fileName=paste0(pngFilePrefix, "-cmanhattan"), fileType="png")
##snpDensity(data, toFile=T, fileName=paste0(pngFilePrefix, "-snp-density"), fileType="png")
qq(fdata, toFile=T, fileName=paste0(pngFilePrefix, "-qq"), fileType="png")

message("Generating PDFs")
manhattan(fdata, annotation, toFile=T, fileName=paste0(pdfFilePrefix, "-annotated-manhattan"), fileType="pdf")
manhattan(fdata, NULL, toFile=T, fileName=paste0(pngFilePrefix, "-manhattan"), fileType="pdf")
##cmanhattan(fdata, NULL, toFile=T, fileName=paste0(pdfFilePrefix, "-cmanhattan"), fileType="pdf")
## qq(data, toFile=T, fileName=paste0(pdfFilePrefix, "-qq"), fileType="pdf")
snpDensity(data, toFile=T, fileName=paste0(pdfFilePrefix, "-snp-density", fileType="pdf")

##message("Generating ploty Manhattans")
## fdata  <- filterData(data, 0.05)

quit(save="no", status=0)

