## 'manhattan' modified from qqman manhattan: https://github.com/stephenturner/qqman/blob/ab8e05f18e3d4888c84c45ac912295742eb2c055/R/manhattan.R
##

library(calibrate)



chr2numeric  <- function(x) {
    chrlabs = unique(x)
    chrOrder <-c((1:22),"X","Y","M")
    chrlabs = sort(factor(chrlabs,levels=chrOrder, ordered=TRUE))
    if ("X" %in% x) {
        x[x == "X"]  <- 23
    }
    if ("Xp" %in% x) {
        x[x == "Xp"]  <- 24
    }
    if ("Y" %in% x) {
        x[x == "Y"]  <- 25
    }
    if ("M" %in% x) {
        x[x == "M"]  <- 26
    }

    list(chr = x, chrlabs = chrlabs)
}


manhattan <- function(x, chr="CHR", bp="BP", p="P", snp="SNP", labelSize=0.45,
                      col=c("gray70","grey38"), chrlabs=NULL,
                      suggestiveline=-log10(1e-5), genomewideline=-log10(5e-8), 
                      highlight=NULL, logp=TRUE, annotatePval = NULL, annotateTop = TRUE, ...) {

    # Not sure why, but package check will warn without this.
    CHR=BP=P=index=NULL
    
    # Check for sensible dataset
    ## Make sure you have chr, bp and p columns.
    if (!(chr %in% names(x))) stop(paste("Column", chr, "not found!"))
    if (!(bp %in% names(x))) stop(paste("Column", bp, "not found!"))
    if (!(p %in% names(x))) stop(paste("Column", p, "not found!"))
    ## warn if you don't have a snp column
    if (!(snp %in% names(x))) warning(paste("No SNP column found. OK unless you're trying to highlight."))
    ## make sure chr, bp, and p columns are numeric.
    if (!is.numeric(x[[chr]])) {
        adjustChr = chr2numeric(x[[chr]])
    }
    else {
        adjustChr = list(chr = x[[chr]], chrlabs = NULL)
    }
        # stop(paste(chr, "column should be numeric. Do you have 'X', 'Y', 'MT', etc? If so change to numbers and try again."))
    if (!is.numeric(x[[bp]])) stop(paste(bp, "column should be numeric."))
    if (!is.numeric(x[[p]])) stop(paste(p, "column should be numeric."))
    
    # Create a new data.frame with columns called CHR, BP, and P.
    d=data.frame(CHR=adjustChr[["chr"]], BP=x[[bp]], P=x[[p]])
    chrlabs = adjustChr[["chrlabs"]]
    
    # If the input data frame has a SNP column, add it to the new data frame you're creating.
    if (!is.null(x[[snp]])) d=transform(d, SNP=x[[snp]])
    
    # Set positions, ticks, and labels for plotting
    ## Sort and keep only values where is numeric.
    #d <- subset(d[order(d$CHR, d$BP), ], (P>0 & P<=1 & is.numeric(P)))
    d <- subset(d, (is.numeric(CHR) & is.numeric(BP) & is.numeric(P)))
    d <- d[order(d$CHR, d$BP), ]
    #d$logp <- ifelse(logp, yes=-log10(d$P), no=d$P)
    if (logp) {
        d$logp <- -log10(d$P)
    } else {
        d$logp <- d$P
    }
    d$pos=NA
    
    
    # Fixes the bug where one chromosome is missing by adding a sequential index column.
    d$index=NA
    ind = 0
    for (i in unique(d$CHR)){
        ind = ind + 1
        d[d$CHR==i,]$index = ind
    }
    
    # This section sets up positions and ticks. Ticks should be placed in the
    # middle of a chromosome. The a new pos column is added that keeps a running
    # sum of the positions of each successive chromsome. For example:
    # chr bp pos
    # 1   1  1
    # 1   2  2
    # 2   1  3
    # 2   2  4
    # 3   1  5
    nchr = length(unique(d$CHR))
    if (nchr==1) { ## For a single chromosome
        ## Uncomment the next two linex to plot single chr results in Mb
        #options(scipen=999)
	    #d$pos=d$BP/1e6
        d$pos=d$BP
        ticks=floor(length(d$pos))/2+1
        xlabel = paste('Chromosome',unique(d$CHR),'position')
        labs = ticks
    } else { ## For multiple chromosomes
        lastbase=0
        ticks=NULL
        for (i in unique(d$index)) {
            if (i==1) {
                d[d$index==i, ]$pos=d[d$index==i, ]$BP
            } else {
                lastbase=lastbase+tail(subset(d,index==i-1)$BP, 1)
                d[d$index==i, ]$pos=d[d$index==i, ]$BP+lastbase
            }
            # Old way: assumes SNPs evenly distributed
            # ticks=c(ticks, d[d$index==i, ]$pos[floor(length(d[d$index==i, ]$pos)/2)+1])
            # New way: doesn't make that assumption
            ticks = c(ticks, (min(d[d$index == i,]$pos) + max(d[d$index == i,]$pos))/2 + 1)
        }
        xlabel = 'Chromosome'
        #labs = append(unique(d$CHR),'') ## I forgot what this was here for... if seems to work, remove.
        labs <- unique(d$CHR)
    }
    
    # Initialize plot
    xmax = ceiling(max(d$pos) * 1.03)
    xmin = floor(max(d$pos) * -0.03)
    
    # The old way to initialize the plot
    # plot(NULL, xaxt='n', bty='n', xaxs='i', yaxs='i', xlim=c(xmin,xmax), ylim=c(ymin,ymax),
    #      xlab=xlabel, ylab=expression(-log[10](italic(p))), las=1, pch=20, ...)

    
    # The new way to initialize the plot.
    ## See http://stackoverflow.com/q/23922130/654296
    ## First, define your default arguments
    def_args <- list(xaxt='n', bty='n', xaxs='i', yaxs='i', las=1, pch=20,
                     xlim=c(xmin,xmax), ylim=c(0,ceiling(max(d$logp))),
                     xlab=xlabel, ylab=expression(-log[10](italic(p))))
    ## Next, get a list of ... arguments
    #dotargs <- as.list(match.call())[-1L]
    dotargs <- list(...)
    ## And call the plot function passing NA, your ... arguments, and the default
    ## arguments that were not defined in the ... arguments.
    do.call("plot", c(NA, dotargs, def_args[!names(def_args) %in% names(dotargs)]))
    
    # If manually specifying chromosome labels, ensure a character vector and number of labels matches number chrs.
    if (!is.null(chrlabs)) {
        if (is.character(chrlabs)) {
            if (length(chrlabs)==length(labs)) {
                labs <- chrlabs
            } else {
                warning("You're trying to specify chromosome labels but the number of labels != number of chromosomes.")
            }
        } else {
            warning("If you're trying to specify chromosome labels, chrlabs must be a character vector")
        }
    }
    
    # Add an axis. 
    if (nchr==1) { #If single chromosome, ticks and labels automatic.
        axis(1, ...)
    } else { # if multiple chrs, use the ticks and labels you created above.
        axis(1, at=ticks, labels=labs, ...)
    }
    
    # Create a vector of alternatiting colors
    col=rep(col, max(d$CHR))

    # Add points to the plot
    if (nchr==1) {
        with(d, points(pos, logp, pch=20, col=col[1], ...))
    } else {
        # if multiple chromosomes, need to alternate colors and increase the color index (icol) each chr.
        icol=1
        for (i in unique(d$index)) {
            with(d[d$index==unique(d$index)[i], ], points(pos, logp, col=col[icol], pch=20, ...))
            icol=icol+1
        }
    }
    
    # Add suggestive and genomewide lines
    if (suggestiveline) abline(h=suggestiveline, col="blue")
    if (genomewideline) abline(h=genomewideline, col="red")
    
    # Highlight snps from a character vector
    if (!is.null(highlight)) {
        if (any(!(highlight %in% d$SNP))) warning("You're trying to highlight SNPs that don't exist in your results.")
        d.highlight=d[which(d$SNP %in% highlight), ]
        with(d.highlight, points(pos, logp, col="green3", pch=20, ...)) 
    }
    
    # Highlight top SNPs
    if (!is.null(annotatePval)) {
        # extract top SNPs at given p-val
        topHits = subset(d, P <= annotatePval)
        par(xpd = TRUE)
        # annotate these SNPs
        if (annotateTop == FALSE) {
            with(subset(d, P <= annotatePval),
                 textxy(pos, -log10(P), offset = 0.625, labs = topHits$SNP, cex = labelSize), ...)
        }
        else {
            # could try alternative, annotate top SNP of each sig chr
            topHits <- topHits[order(topHits$P),]
            topSNPs <- NULL
            
            for (i in unique(topHits$CHR)) {
                
                chrSNPs <- topHits[topHits$CHR == i,]
                topSNPs <- rbind(topSNPs, chrSNPs[1,])
                
            }
            textxy(topSNPs$pos, -log10(topSNPs$P), offset = 0.625, labs = topSNPs$SNP, cex = labelSize, ...)
        }
    }  
    par(xpd = FALSE)
}



generateGeneAnnotationObj  <- function(data, genePeaks) {
    annObj  <- rep(1, length(data$P))
    levelCount  <- 2
    for (index in 1:nrow(genePeaks)) {
        row  <- genePeaks[index, ]
        annObj[with(data, CHR == row$chromosome & BP >= row$location_start & BP <= row$location_end)]  <- levelCount
        levelCount = levelCount + 1
    }
    finalCount = levelCount - 1
    annObj <- factor(annObj, levels=1:finalCount, labels = c("", genePeaks$gene_symbol))
    annObj
}


findGenePeaks  <- function(genes) {
    peaks  <- genes[genes$num_sig_variants > 0, ]

    ## assume first bin is the biggest, ignore those as a first passs
    ## possible 3rd quartile twice
    h  <- hist(peaks$num_sig_variants[peaks$num_sig_variants > 0])
    cutoff  <- h$breaks[2]
    peaks <- peaks[peaks$num_sig_variants >= cutoff, ]
    is_top_peak  <- peaks$num_sig_variants >= summary(peaks$num_sig_variants)["3rd Qu."]
    peaks  <- cbind(peaks, is_top_peak)
    peaks
}
