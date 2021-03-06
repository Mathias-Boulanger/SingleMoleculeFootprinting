% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/single_molecule_manipulation_functions.r
\name{BinMethylation}
\alias{BinMethylation}
\title{Summarize methylation inside sorting bins}
\usage{
BinMethylation(MethSM, Bin)
}
\arguments{
\item{MethSM}{Single molecule matrix}

\item{Bin}{IRanges object with absolute coordinates for single sorting bin.}
}
\value{
Reads covering bin with their summarized methylation status
}
\description{
Summarize methylation inside sorting bins
}
\examples{

TFBSs = GenomicRanges::GRanges("chr6", IRanges(c(88106253), c(88106263)), strand = "-")
elementMetadata(TFBSs)$name = c("NRF1")
names(TFBSs) = c(paste0("TFBS_", c(4305216)))

TFBS_center = start(TFBS) + (end(TFBS)-start(TFBS))/2
BinsCoordinates = IRanges(start = c(TFBS_center+bins[[1]][1], TFBS_center+bins[[2]][1], TFBS_center+bins[[3]][1]),
                          end = c(TFBS_center+bins[[1]][2], TFBS_center+bins[[2]][2], TFBS_center+bins[[3]][2]))

binMethylationValues = BinMethylation(MethSM = MethSM, Bin = BinsCoordinates[1]))

}
