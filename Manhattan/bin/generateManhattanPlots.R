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
## cap
cap  <- 50
if (!is.na(args[3])) {cap  <-  args[3]}
## plottype
plotType  <- "all"
if (!is.na(args[4])) {plotType  <-  args[4]}



GUS_HOME  <-  Sys.getenv("GUS_HOME")
MANHATTAN_SCRIPT  <- paste(GUS_HOME, "lib/R/Manhattan/circular_manhattan.R", sep="/")
PLOTLY_SCRIPT  <- paste(GUS_HOME, "lib/R/Manhattan/plotly_manhattan.R", sep="/");
source(MANHATTAN_SCRIPT);
source(PLOTLY_SCRIPT);
library(data.table) # for faster read and progress bar
library(htmlwidgets)

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

if (plotType == "all" || plotType == "plotly") {
    if (nrow(data) > 100000) {
        message("Filtering data p < 0.001")
        fdata  <- filterData(data, 0.001, withAnnotation=TRUE)
    }
    else {
        fdata  <- filterData(data, NULL, withAnnotation=TRUE)
    }
    message("Generating Plotly Graph")
    pGraph <- plotly_manhattan(fdata, fileName=filePrefix, cap=cap)
    pGraphJson <- htmlwidgets:::toJSON(pGraph)
    write(pGraphJson, paste0(filePrefix, "-manhattan.json"))
}

if (plotType == "all" || plotType == "png") {
    message("Filtering data p < 0.5")
    fdata  <- filterData(data, 0.5, withAnnotation=FALSE)
    message("Generating PNGs")
    message("Generating PNGs - Annotated Manhattan")
    manhattan(fdata, track, annotation, toFile=T, fileName=paste0(pngFilePrefix, "-annotated-manhattan"), fileType="png")
    message("Generating PNGs - Manhattan")
    manhattan(fdata, track,  NULL, toFile=T, fileName=paste0(pngFilePrefix, "-manhattan"), fileType="png")
    # message("Generating PNGs - Circular Manhattan")
    # cmanhattan(fdata, track, NULL, toFile=T, fileName=paste0(pngFilePrefix, "-cmanhattan"), fileType="png")
    # message("Generating PNGs - SNP Density")
    # snpDensity(data, track, toFile=T, fileName=paste0(pngFilePrefix, "-snp-density"), fileType="png")
    # message("Generating PNGs - QQ")
    # qq(data, track, toFile=T, fileName=paste0(pngFilePrefix, "-qq"), fileType="png")
}

##message("Generating PDFs")
##manhattan(fdata, track, annotation, toFile=T, fileName=paste0(pdfFilePrefix, "-annotated-manhattan"), fileType="pdf")
##manhattan(fdata, track, NULL, toFile=T, fileName=paste0(pngFilePrefix, "-manhattan"), fileType="pdf")
##cmanhattan(fdata, track, NULL, toFile=T, fileName=paste0(pdfFilePrefix, "-cmanhattan"), fileType="pdf")
## qq(data, track, toFile=T, fileName=paste0(pdfFilePrefix, "-qq"), fileType="pdf")
##snpDensity(data, track, toFile=T, fileName=paste0(pdfFilePrefix, "-snp-density", fileType="pdf")


quit(save="no", status=0)

