% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/context_methylation_functions.r
\name{GetQuasRprj}
\alias{GetQuasRprj}
\title{Get QuasRprj}
\usage{
GetQuasRprj(sampleSheet, genome)
}
\arguments{
\item{sampleSheet}{QuasR pointer file}

\item{genome}{BSgenome}
}
\description{
Get QuasRprj
}
\examples{

Qinput = system.file("extdata", "QuasR_input_pairs.txt", package = "SingleMoleculeFootprinting", mustWork = T)
QuasRprj = GetQuasRprj(Qinput, BSgenome.Mmusculus.UCSC.mm10)

}
