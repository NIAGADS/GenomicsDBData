source(paste0(Sys.getenv("GUS_HOME"), "/lib/R/Manhattan/CMplot.r"))

chrLabels  <- function(x) {
    chrlabs = unique(x)
    chrOrder <-c((1:22),"X","Y","M")
    sort(factor(chrlabs,levels=chrOrder, ordered=TRUE))
}

filterData  <- function(data, filter=NULL, withAnnotation=FALSE) {

    if (!is.null(filter)) {
        cdata  <- data[data$neg_log10_pvalue > -log10(filter), ]
    }
    else {
        cdata  <- data
    }

    if (withAnnotation) {
        cdata  <- data[, c("variant_record_primary_key", "CHR", "BP", "P", "SNP", "neg_log10_pvalue", "GENE")]
        colnames(cdata)  <- c("SNP", "CHR", "BP", "P", "LABEL", "NEG_LOG10P", "GENE")
    }
    else {
        cdata  <- cdata[, c("variant_record_primary_key", "CHR", "BP", "P")]
        colnames(cdata)  <- c("SNP", "CHR", "BP", "P")
    }
    
    cdata
}


filterHighlight  <- function(annotation, maxHits = 20) {
    ## when some hits are significant, only label those
    numGwSig  <- sum(annotation$is_significant == 1)
    numSig  <- sum(annotation$is_significant == 2)
    totalSig  <- numGwSig + numSig
    if (totalSig  == 0) {
        return(NULL)
    }

    if (numGwSig == 0) { # just return the top 5 hits
        return(annotation[1:5, ])
    }

    ## isolate significant results
    fAnnotation  <- annotation[annotation$is_significant == 1, ]

    if (numGwSig > maxHits) {
        ## filter for genes
        gAnnotation  <- filterHighlightsByType(fAnnotation, maxHits, "gene", "protein coding")
        numGeneHits  <- nrow(gAnnotation)

        if (numGeneHits < maxHits) {
            remainingAllowableHits = maxHits - numGeneHits
            vAnnotation  <- filterHighlightsByType(fAnnotation, remainingAllowableHits, "variant")
            return(rbind(gAnnotation, vAnnotation))
        }
        else {
            return(gAnnotation)
        }

    }

    ## otherwise return hits w/genome wide significance
    return(fAnnotation);
}

filterHighlightsByType  <- function(annotation, maxHits, hitType="gene", hitSubType=NULL) {

    fAnnotation  <- annotation[annotation$hit_type == hitType, ]

    if (!is.null(hitSubType)) {
        fAnnotation  <- fAnnotation[fAnnotation$hit_subtype == hitSubType, ]
    }

    if (nrow(fAnnotation) > maxHits) {
        fAnnotation  <- fAnnotation[1:maxHits, ]
    }

    return(fAnnotation)
}

cmanhattan <- function(cdata, track, r=1, toFile=FALSE, fileName="cmanhattan", fileType="png") {

    chrLabels = chrLabels(cdata$CHR)

    CMplot(data,type="p", plot.type="c", r=1,
           col=c("grey30","grey60"),
           chr.labels=chrLabels,
           threshold=c(5e-8,1e-5),
           cir.chr.h=0.5,
           amplify=TRUE,
           threshold.lty=c(1,2),
           threshold.col=c("red","blue"),
           signal.line=1,
           chr.den.col=c("darkgreen","yellow","red"),
           signal.col=c("red","blue"),
           bin.size=5e6,
           outward=FALSE,
           width=10,height=10,
           file.output=toFile,
           file.name=fileName,
           file=fileType,
           main=track,
           signal.cex = 0.4, cex=c(0.2,0.4,1))
}


generateHighlight  <- function(annotation) {
    ## identify top SNP per gene and label

    if (is.null(annotation)) {
        return (NULL)
    }

    ## filter for annotation that have significant variants
    fAnnotation  <- filterHighlight(annotation)
    if (is.null(fAnnotation)) {
        return (NULL)
    }

    highlightSNPs  <-  NULL
    highlightFeatures  <- NULL

    for (index in 1:nrow(fAnnotation)) {
        highlightSNPs  <- c(highlightSNPs, fAnnotation[index, "variant"])
        highlightFeatures <- c(highlightFeatures, fAnnotation[index, "hit_display_value"])
    }

    list(snps = highlightSNPs, features = highlightFeatures, significanceLevel = fAnnotation[1, "is_significant"])

}


snpDensity  <- function(data, track, toFile=FALSE, fileName="snp-density", fileType="png") {
    cdata  <- filterData(data, 1e-5, withAnnotation=FALSE)
    CMplot(cdata,
           plot.type="d",
           bin.size=5e5,
           chr.den.col=c("darkgreen", "yellow", "red"),
           file=fileType,
           file.output=toFile,
           file.name=fileName,
           width=9,
           height=6,
           main=paste0(track, " - No. Variants (p < 1e-5)")
    )
}

qq <- function(data, track, toFile=FALSE, fileName="qq", fileType="png") {
    cdata  <- filterData(data, filter=NULL, withAnnotation=FALSE)
    data$P  <- 10**(-1 * data$neg_log10_pvalue)
    CMplot(data,plot.type="q",
           box=FALSE,
           file=fileType,
           conf.int=TRUE,
           conf.int.col=NULL,
           threshold.col="red",
           threshold.lty=2,
           file.output=toFile,
           file.name=fileName,
           width=5,
           height=5,
           main=track,
           verbose=TRUE
           )
}

manhattan  <- function(cdata, track, annotation=NULL, toFile=FALSE, fileName="manhattan", fileType="png") {


    chrLabels = chrLabels(cdata$CHR)

    highlights  <- generateHighlight(annotation)

    if(is.null(highlights)) {
        CMplot(cdata, plot.type="m",
               chr.labels=chrLabels,
               LOG10=TRUE, ylim=NULL,
               col=c("grey30","grey60"),
               threshold=c(5e-8,1e-5),
               threshold.col=c("red","blue"),
               threshold.lty=c(1,2),
               threshold.lwd=c(1,1),
               amplify=TRUE,
               bin.size=5e6,
               chr.den.col=c("darkgreen", "yellow", "red"),
               signal.col=c("red","blue"),
               signal.cex=0.5,
               signal.pch=c(19,19),
               cex=c(0.2,0.5,1),
               file.output=toFile,
               file=fileType,
               file.name=fileName,
               main=track,
               highlight.text.cex=1.4,
               width=18,height=6)
    } else {
        highlightColor  <- "green"
        CMplot(cdata, plot.type="m",
               chr.labels=chrLabels,
               LOG10=TRUE, ylim=NULL,
               col=c("grey30","grey60"),
                threshold=c(5e-8,1e-5),
               threshold.col=c("red","blue"),
               threshold.lty=c(1,2),
               threshold.lwd=c(1,1),
               amplify=TRUE,
               bin.size=5e6,
               chr.den.col=c("darkgreen", "yellow", "red"),
               signal.col=c("red","blue"),
               signal.cex=0.5,
               signal.pch=c(19,19),
               cex=c(0.2,0.5,1),
               file.output=toFile,
               file=fileType,
               file.name=fileName,
               highlight.text=highlights$features,
               highlight=highlights$snps,
               highlight.col=highlightColor,
               highlight.text.cex=1.1,
               width=18,height=6)
    }
}

