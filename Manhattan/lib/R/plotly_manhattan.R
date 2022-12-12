## adapted from https://r-graph-gallery.com/101_Manhattan_plot.html

library(htmlwidgets)
library(plotly)
library(tidyverse)

plotly_manhattan  <- function(data, fileName) {   
    ## Prepare the dataset
    plotData <- data  %>%

    ## Compute chromosome size
    group_by(CHR) %>%
    summarise(chr_len=max(BP)) %>%

    ## Calculate cumulative position of each chromosome
    mutate(tot=cumsum(as.numeric(chr_len))-chr_len) %>%
    select(-chr_len) %>%

    ## Add this info to the initial dataset
    left_join(data, ., by=c("CHR"="CHR")) %>%

    ## Add a cumulative position of each SNP
    arrange(CHR, BP) %>%
    mutate( BPcum=BP+tot)

    ## Add highlight and annotation information
    ## mutate( is_highlight=ifelse(SNP %in% snpsOfInterest, "yes", "no")) %>%

    ## Prepare X axis
    axisdf <- plotData %>% group_by(CHR) %>% summarize(center=( max(BPcum) + min(BPcum) ) / 2 )

    ## Prepare text description for each SNP:
    plotData$text <- paste("Variant: ", plotData$LABEL, "\nPosition: ",
                           plotData$BP, "\nChromosome: ", paste0('chr',plotData$CHR),
                           "\np-value:", formatC(10**(-1*plotData$NEG_LOG10P), format="e", digits=2),
                           "\nImpacted Gene: ", plotData$GENE,
                           sep="")


    gws <- -log10(5e-8)
    sig <- 6
    yUpperLim <- min(25, max(plotData$NEG_LOG10P)) # 25 is the cap
    
    ## Make the plot -- want to use the capped values, not the actual
    p <- ggplot(plotData, aes(x=BPcum, y=-log10(P), text=text)) +

    ## Show all points
    geom_point( aes(color=as.factor(CHR)), alpha=0.8, size=1.3) +
    scale_color_manual(values = rep(c("black", "grey"), 22 )) +

    geom_hline(yintercept = gws, linetype = "dashed", color = "red") + 
    geom_hline(yintercept = sig, linetype = "dashed", color = "blue") +

 
    ## custom X axis:
    scale_x_continuous( label = axisdf$CHR, breaks= axisdf$center ) +
    scale_y_continuous(expand = c(0, 0) ) +     ## remove space between plot area and x axis
    ylim(min(plotData$NEG_LOG10P), yUpperLim) +

    xlab("BP") + 

    ## Add highlighted points
                                        # geom_point(data=subset(plotData, is_highlight=="yes"), color="orange", size=2) +

    geom_point(data = plotData %>% filter(NEG_LOG10P >= gws), color = "red") +
    geom_point(data = plotData %>% filter(NEG_LOG10P >= sig & NEG_LOG10P < gws), color = "blue") + 
  
    
    ## Custom the theme:
    theme_bw() +
    theme(
        legend.position="none",
        panel.border = element_blank(),
        panel.grid.major.x = element_blank(),
        panel.grid.minor.x = element_blank()
    )

    saveWidget(ggplotly(p, tooltip="text"), file = paste0(fileName, ".html"), selfcontained=FALSE);
    # system('rm -r test_files')
}
