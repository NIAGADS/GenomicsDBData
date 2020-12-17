library(CMplot)



chrLabels  <- function(x) {
    chrlabs = unique(x)
    chrOrder <-c((1:22),"X","Y","M")
    sort(factor(chrlabs,levels=chrOrder, ordered=TRUE))
}

cmanhattan <- function(data, r=1, toFile=FALSE, suffix="", filter=NULL, annotation=NULL) { 

    cdata  <- data[, c("SNP", "CHR", "BP", "P", "neg_log10_pvalue")]
    
    if (!is.null(filter)) {
        cdata  <- cdata[cdata$neg_log10_pvalue > -log10(filter), ]
    }
    
    chrLabels = chrLabels(cdata$CHR)

    
    CMplot(cdata,type="p", plot.type="c", r=1,
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
           file="pdf",
           memo=suffix,
           signal.cex = 0.4, cex=c(0.2,0.4,1))

}


generateHighlight  <- function(data, genes) {
    ## identify top SNP per gene and label
    
    if (is.null(genes)) {
        return (NULL)
    }

    ## filter for  genes that have significant variants
    sigGindex  <- genes$num_sig_variants > 0
    if (sum(sigGindex) == 0) {
        return (NULL)
    }
    
    sigG  <- genes[sigGindex, ]
    
    highlightSNPs  <-  NULL
    highlightGenes  <- NULL

    for (index in 1:nrow(sigG)) {
        sg <- sigG[index, ]
        variants  <- sg$variants
        
        subset  <-  data[data$variant_record_primary_key %in% unlist(strsplit(variants, split=",")), ]
        subset  <- subset[order(-subset$neg_log10_pvalue), ]

        highlightSNPs  <- c(highlightSNPs, subset$SNP[1])
        highlightGenes <- c(highlightGenes, sg$gene_symbol)
    }

    list(snps = highlightSNPs, genes = highlightGenes)

}

manhattan  <- function(data, genes=NULL, toFile=FALSE, fileName="", filter=NULL, annotation=NULL) { 

    cdata  <- data[, c("SNP", "CHR", "BP", "P", "neg_log10_pvalue")]
    
    if (!is.null(filter)) {
        cdata  <- cdata[cdata$neg_log10_pvalue > -log10(filter), ]
    }

    chrLabels = chrLabels(cdata$CHR)

    highlights  <- generateHighlight(data, genes)

    if(is.null(highlights)) {    
        CMplot(cdata, plot.type="m",
               LOG10=TRUE, ylim=NULL,
               col=c("grey30","grey60"),
               threshold=c(1e-6,1e-4),
               threshold.lty=c(1,2),
               threshold.lwd=c(1,1),
               threshold.col=c("black","grey"),
               amplify=TRUE,
               bin.size=5e6,
               chr.den.col=c("darkgreen", "yellow", "red"),
               signal.col=c("red","blue"),
               signal.cex=0.5,
               signal.pch=c(19,19),
               cex=c(0.2,0.5,1),
               file.output=toFile,
               file="pdf",
               memo=fileName,
               ##highlight.text=topSNPs,
               ##highlight=topSNPs,
               highlight.text.cex=1.4,
               width=18,height=6)
    } else {
        CMplot(cdata, plot.type="m",
               LOG10=TRUE, ylim=NULL,
               col=c("grey30","grey60"),
               threshold=c(1e-6,1e-4),
               threshold.lty=c(1,2),
               threshold.lwd=c(1,1),
               threshold.col=c("black","grey"),
               amplify=TRUE,
               bin.size=5e6,
               chr.den.col=c("darkgreen", "yellow", "red"),
               signal.col=c("red","blue"),
               signal.cex=0.5,
               signal.pch=c(19,19),
               cex=c(0.2,0.5,1),
               file.output=toFile,
               file="pdf",
               memo=fileName,
               highlight.text=highlights$genes,
               highlight=highlights$snps,
               highlight.text.cex=1.4,
               width=18,height=6)
    }
}
