#' Get QuasRprj
#'
#' @param sampleSheet QuasR pointer file
#' @param genome BSgenome
#'
#' @import QuasR
#'
#' @export
#'
#' @examples
#'
#' Qinput = system.file("extdata", "QuasR_input_pairs.txt", package = "SingleMoleculeFootprinting", mustWork = T)
#' QuasRprj = GetQuasRprj(Qinput, BSgenome.Mmusculus.UCSC.mm10)
#'
GetQuasRprj = function(sampleSheet, genome){

  QuasRprj=QuasR::qAlign(sampleFile=sampleSheet,
                        genome=genome@pkgname,
                        projectName = "prj",
                        paired="fr",
                        aligner = "Rbowtie",
                        bisulfite="undir")
  QuasRprj@aligner = "Rbowtie"

  return(QuasRprj)

}

#' Get Single Molecule methylation matrix
#'
#' Used internally as the first step in CallContextMethylation
#'
#' @param QuasRprj QuasR project object as returned by calling the QuasR function qAling on previously aligned data
#' @param range GenimocRange representing the genomic region of interest
#' @param sample One of the sample names as reported in the SampleName field of the QuasR pointer file provided to qAlign. N.b. all the files with the passed sample name will be used to call methylation
#'
#' @import QuasR
#' @importFrom data.table data.table
#' @importFrom data.table dcast
#' @importFrom IRanges isEmpty
#'
#' @return List of single molecule methylation matrixes (all Cytosines), one per sample
#'
#' @export
#'
#' @examples
#'
#' Qinput = system.file("extdata", "QuasR_input_pairs.txt", package = "SingleMoleculeFootprinting", mustWork = T)
#' QuasRprj = GetQuasRprj(Qinput, BSgenome.Mmusculus.UCSC.mm10)
#' sample = suppressMessages(readr::read_delim(Qinput, delim = "\t")[[2]])
#' range = GRanges(seqnames = "chr6", ranges = IRanges(start = 88106000, end = 88106500), strand = "*")
#'
#' MethSM = GetSingleMolMethMat(QuasRprj, range, sample)
#'
GetSingleMolMethMat = function(QuasRprj,range,sample){

  QuasRprj_sample = QuasRprj[unlist(lapply(unique(sample), function(s){grep(s, QuasRprj@alignments$SampleName)}))]
  Cs=QuasR::qMeth(QuasRprj_sample, query=range, mode="allC",reportLevel="alignment", collapseBySample = TRUE)
  # use data.table to get a 1,0 matrix of methylation profiles
  MethMatrix_list = lapply(seq_along(Cs), function(i){
    dt = data.table::data.table(meth=Cs[[i]]$meth, aid=Cs[[i]]$aid, cid=Cs[[i]]$Cid)
    if (any(isEmpty(dt))){
      message(paste0("No single molecule methylation info found in the given range for sample ", names(Cs)[i]))
      meth_matrix = NULL
      meth_matrix
    } else {
      spread_dt = data.table::dcast(dt, aid ~ cid, value.var = "meth", )
      meth_matrix = as.matrix(spread_dt, rownames = "aid")
      meth_matrix
    }
  })

  return(MethMatrix_list)
}

#' Calculate reads conversion rate
#'
#' @param MethSM as comes out of the func GetSingleMolMethMat
#' @param chr Chromosome, MethSM doesn't carry this info
#' @param genome BSgenome
#' @param thr Double between 0 and 1. Threshold below which to filter reads.
#'
#' @import GenomicRanges
#' @import Biostrings
#' @importFrom IRanges IRanges
#'
#' @return Filtered MethSM
#'
#' @export
#'
#' @examples
#'
#' Qinput = system.file("extdata", "QuasR_input_pairs.txt", package = "SingleMoleculeFootprinting", mustWork = T)
#' QuasRprj = GetQuasRprj(Qinput, BSgenome.Mmusculus.UCSC.mm10)
#' sample = suppressMessages(readr::read_delim(Qinput, delim = "\t")[[2]])
#' range = GRanges(seqnames = "chr6", ranges = IRanges(start = 88106000, end = 88106500), strand = "*")
#' MethSM = GetSingleMolMethMat(QuasRprj, range, sample)
#'
#' MethSM = FilterByConversionRate(MethSM, chr = "chr19", genome = BSgenome.Mmusculus.UCSC.mm10, thr = 0.8)
#'
FilterByConversionRate = function(MethSM, chr, genome, thr){

  CytosineRanges = GRanges(chr,IRanges(as.numeric(colnames(MethSM)),width = 1))
  GenomicContext = Biostrings::getSeq(genome, resize(CytosineRanges,3,fix='center'))
  IsInContext = Biostrings::vcountPattern('GC',GenomicContext)==1 | vcountPattern('CG',GenomicContext)==1

  # filter based on conversion
  ConvRate=rowMeans(MethSM[,!IsInContext, drop=FALSE],na.rm=TRUE)
  message(paste0(100 - round((sum(ConvRate<thr)/length(ConvRate))*100, digits = 2), "% of reads found with conversion rate below ", thr))
  FilteredSM = MethSM[ConvRate<thr,, drop=FALSE]

  return(FilteredSM)

}

#' Detect type of experiment
#'
#' @param Samples SampleNames field from QuasR sampleSheet
#'
#' @export
#'
#' @examples
#'
#' Qinput = system.file("extdata", "QuasR_input_pairs.txt", package = "SingleMoleculeFootprinting", mustWork = T)
#' QuasRprj = GetQuasRprj(Qinput, BSgenome.Mmusculus.UCSC.mm10)
#' Samples = QuasR::alignments(QuasRprj)[[1]]$SampleName
#'
#' ExpType = DetectExperimentType(Samples)
#'
DetectExperimentType = function(Samples){

  if(length(grep("_NO_", Samples)) > 0){
    ExpType = "NO"
  }else if(length(grep("_SS_",Samples)) > 0){
    ExpType = "SS"
  }else if(length(grep("_DE_",Samples)) > 0){
    ExpType = "DE"
  }else{stop("Sample name error. No _McvPI_ , _SsssI_ or _McvPISsssI_")}

  message(paste0("Detected experiment type: ", ExpType))
  return(ExpType)

}

#' Filter Cytosines in context
#'
#' @param MethGR Granges obj of average methylation
#' @param genome BSgenome
#' @param context Context of interest (e.g. "GC", "CG",..)
#'
#' @import GenomicRanges
#' @import Biostrings
#'
#' @return filtered Granges obj
#'
#' @export
#'
#' @examples
#'
#' Qinput = system.file("extdata", "QuasR_input_pairs.txt", package = "SingleMoleculeFootprinting", mustWork = T)
#' QuasRprj = GetQuasRprj(Qinput, BSgenome.Mmusculus.UCSC.mm10)
#' Samples = QuasR::alignments(QuasRprj)[[1]]$SampleName
#' sample = Samples[1]
#' MethGR = QuasR::qMeth(QuasRprj[grep(sample, Samples)], mode="allC", range, collapseBySample = TRUE, keepZero = TRUE)
#'
#' FilterContextCytosines(MethGR, BSgenome.Mmusculus.UCSC.mm10, "NGCNN")
#'
FilterContextCytosines = function(MethGR, genome, context){

  CytosineRanges = GRanges(seqnames(MethGR), ranges(MethGR), strand(MethGR)) # performing operation without metadata to make it lighter
  seqinfo(CytosineRanges) = seqinfo(MethGR)

  NewWidth = ifelse(nchar(context) %% 2 == 1, nchar(context), nchar(context) + 1) # Make context nchar() odd so we can fix to 'center'
  GenomicContext = Biostrings::getSeq(genome, suppressWarnings(trim(IRanges::resize(CytosineRanges, width = NewWidth, fix = "center"))), as.character = FALSE)# I checked: it is strand-aware

  # Fix the truncated sites
  trimmed <- which(!width(GenomicContext) == NewWidth)
  for(k in trimmed){
    if(as.character(strand(CytosineRanges[k])) == '+'){
      GenomicContext[k] <- paste0(c(rep('N', 5-width(GenomicContext[k])), as.character(GenomicContext[k])), collapse="")
    } else if(as.character(strand(CytosineRanges[k])) == '-'){
      GenomicContext[k] <- paste0(c(as.character(GenomicContext[k]), rep('N', 5-width(GenomicContext[k]))), collapse="")
    }
  }

  FixedPattern = !(length(grep("A|C|G|T", strsplit(gsub("N", "", context), "")[[1]], invert = TRUE)) > 0) # check whether we need to use fixed or not in the next function...fixed==TRUE is a tiny bit faster
  IsInContext = Biostrings::vcountPattern(context, subject = GenomicContext, fixed = FixedPattern) > 0

  MethGR_InContext = MethGR[IsInContext]
  MethGR_InContext$GenomicContext = rep(context, length(MethGR_InContext))

  return(MethGR_InContext)

}

#' Collapse strands
#'
#' @param MethGR Granges obj of average methylation
#' @param context "GC" or "CG". Broad because indicates just the directionality of collapse.
#'
#' @import GenomicRanges
#'
#' @return MethGR with collapsed strands (everything turned to - strand)
#'
CollapseStrands = function(MethGR, context){

  if(length(MethGR) == 0){
    return(MethGR)
  }

  # find the + stranded cytosines and make them -
  MethGR_plus = MethGR[strand(MethGR) == "+"]
  start(MethGR_plus) = start(MethGR_plus) + ifelse(grepl("CG", context), +1, -1)
  end(MethGR_plus) = start(MethGR_plus)
  strand(MethGR_plus) = "-"

  # Extract the - Cs
  MethGR_minus = MethGR[strand(MethGR) == "-"]

  # Sum the counts
  ov = findOverlaps(MethGR_plus, MethGR_minus)
  values(MethGR_minus[subjectHits(ov)])[,-length(values(MethGR))] = as.matrix(values(MethGR_minus[subjectHits(ov)])[,-length(values(MethGR_minus))]) + as.matrix(values(MethGR_plus[queryHits(ov)])[,-length(values(MethGR_plus))])

  return(MethGR_minus)

}

#' Collapse strands in single molecule matrix
#'
#' The idea here is that (regardless of context) if a C is on the - strand, calling getSeq on that coord (N.b. unstranded, that's the important bit) will give a "G', a "C" if it's a + strand.
#'
#' @param MethSM Single molecule matrix
#' @param context "GC" or "CG". Broad because indicates just the directionality of collapse.
#' @param genome BSgenome
#' @param chr Chromosome, MethSM doesn't carry this info
#'
#' @import GenomicRanges
#' @import Biostrings
#' @importFrom plyr rbind.fill.matrix
#' @importFrom IRanges IRanges
#'
#' @return Strand collapsed MethSM
#'
CollapseStrandsSM = function(MethSM, context, genome, chr){

  if (is.null(colnames(MethSM))){
    return(MethSM)
  }

  CytosineRanges = GRanges(chr,IRanges(as.numeric(colnames(MethSM)),width = 1))
  GenomicContext = Biostrings::getSeq(genome, CytosineRanges)
  IsMinusStrand = GenomicContext=="G" # no need to select for GC/CG context --> MethSM passed already subset

  # Separate MethSM into - and + strands
  MethSM_minus = MethSM[apply(MethSM[,IsMinusStrand, drop=FALSE], 1, function(i){sum(is.na(i)) != length(i)}) > 0, IsMinusStrand, drop=FALSE]
  MethSM_plus = MethSM[apply(MethSM[,!IsMinusStrand, drop=FALSE], 1, function(i){sum(is.na(i)) != length(i)}) > 0, !IsMinusStrand, drop=FALSE]
  NrPlusReads = dim(MethSM_plus)[1]
  message(paste0(ifelse(is.null(NrPlusReads), 0, NrPlusReads), " reads found mapping to the + strand, collapsing to -"))

  # Turn + into -
  offset = ifelse(grepl("GC", context), -1, +1) # the opposite if I was to turn - into +
  colnames(MethSM_plus) = as.character(as.numeric(colnames(MethSM_plus)) + offset)

  # Merge matrixes
  StrandCollapsedSM = plyr::rbind.fill.matrix(MethSM_minus, MethSM_plus)
  rownames(StrandCollapsedSM) = c(rownames(MethSM_minus), rownames(MethSM_plus))
  StrandCollapsedSM = StrandCollapsedSM[,as.character(sort(as.numeric(colnames(StrandCollapsedSM)))), drop=FALSE]

  return(StrandCollapsedSM)

}

#' Filter Cs for coverage
#'
#' @param MethGR Granges obj of average methylation
#' @param thr converage threshold
#'
#' @import GenomicRanges
#'
#' @return filtered MethGR
#'
CoverageFilter = function(MethGR, thr){

  Tcounts = as.matrix(elementMetadata(MethGR)[grep("_T$", colnames(elementMetadata(MethGR)))])
  Mcounts = as.matrix(elementMetadata(MethGR)[grep("_M$", colnames(elementMetadata(MethGR)))])

  # filter for coverage
  CoverageMask = Tcounts < thr
  Tcounts[CoverageMask] = NA
  Mcounts[CoverageMask] = NA

  # Calculate methylation rate
  MethylationMatrix = Mcounts/Tcounts

  # bind the GRanges with the scores
  elementMetadata(MethGR)[grep("_T$", colnames(elementMetadata(MethGR)))] = Tcounts
  elementMetadata(MethGR)[grep("_M$", colnames(elementMetadata(MethGR)))] = MethylationMatrix
  colnames(elementMetadata(MethGR)) = gsub("_T$", "_Coverage", colnames(elementMetadata(MethGR)))
  colnames(elementMetadata(MethGR)) = gsub("_M$", "_MethRate", colnames(elementMetadata(MethGR)))

  # do the actual filtering
  MethGRFiltered = MethGR[!(rowSums(is.na(elementMetadata(MethGR)[,-length(elementMetadata(MethGR))])) == (length(elementMetadata(MethGR))-1))]

  return(MethGRFiltered)

}

#' Merged GC and CG matrix
#'
#' @param matrixes list of two matrixes to merge, one for GC info and one for CG.
#'
#' @import BiocGenerics
#'
#' @return merged matrix
#'
#' @examples
#'
#' MergedSM = MergeMatrixes(MethSM)
#'
MergeMatrixes = function(matrixes){

  # When some reads only cover either DGCHN or NWCGW positions cbind complains
  if(nrow(matrixes[[1]]) != nrow(matrixes[[2]]) | !(all(sort(rownames(matrixes[[1]])) %in% sort(rownames(matrixes[[2]]))))){

    # Which reads cover only one context?
    DGCHNonly_reads = rownames(matrixes[[1]])[!(rownames(matrixes[[1]]) %in% rownames(matrixes[[2]]))]
    NWCGWonly_reads = rownames(matrixes[[2]])[!(rownames(matrixes[[2]]) %in% rownames(matrixes[[1]]))]
    # Fill two dummy matrices to make the reads equal in the input matrixes
    DGCHNonly_mat = matrix(data = NA, nrow = length(DGCHNonly_reads), ncol = ncol(matrixes[[2]]), dimnames = list(DGCHNonly_reads, colnames(matrixes[[2]])))
    NWCGWonly_mat = matrix(data = NA, nrow = length(NWCGWonly_reads), ncol = ncol(matrixes[[1]]), dimnames = list(NWCGWonly_reads, colnames(matrixes[[1]])))
    # merge the input matrixes to the respective dummy
    matrixes[[1]] = BiocGenerics::rbind(matrixes[[1]], NWCGWonly_mat)
    matrixes[[2]] = BiocGenerics::rbind(matrixes[[2]], DGCHNonly_mat)

  }

  # Sort reads alphanumerically before binding, because cbind doesn't join (I've tested) matrices by rownames
  matrixes[[1]] = matrixes[[1]][sort(rownames(matrixes[[1]])),]
  matrixes[[2]] = matrixes[[2]][sort(rownames(matrixes[[2]])),]
  MergedMatrixes = BiocGenerics::cbind(matrixes[[1]], matrixes[[2]])
  MergedMatrixes = MergedMatrixes[,as.character(sort(as.numeric(colnames(MergedMatrixes))))]

}

#' Call Context Methylation
#'
#' Can deal with multiple samples
#'
#' @export
#'
#' @param sampleSheet QuasR pointer file
#' @param sample for now this works for sure on one sample at the time only
#' @param genome BSgenome
#' @param RegionOfInterest GenimocRange representing the genomic region of interest
#' @param coverage coverage threshold as integer for least number of reads to cover a cytosine for it to be carried over in the analysis. Defaults to 20.
#' @param ConvRate.thr Convesion rate threshold. Double between 0 and 1, defaults to 0.8
#' @param returnSM whether to return the single molecule matrix, defaults to TRUE
#'
#' @import QuasR
#' @import GenomicRanges
#' @import BiocGenerics
#'
#' @return List with two Granges objects: average methylation call (GRanges) and single molecule methylation call (matrix)
#'
#' @examples
#'
#' Qinput = system.file("extdata", "QuasR_input_pairs.txt", package = "SingleMoleculeFootprinting", mustWork = T)
#' MySample = suppressMessages(readr::read_delim(Qinput, delim = "\t")[[2]])
#' Region_of_interest = GRanges(seqnames = "chr6", ranges = IRanges(start = 88106000, end = 88106500), strand = "*")
#'
#' Methylation = CallContextMethylation(sampleSheet = Qinput,
#'                                      sample = MySample,
#'                                      genome = BSgenome.Mmusculus.UCSC.mm10,
#'                                      RegionOfInterest = Region_of_interest,
#'                                      coverage = 20,
#'                                      ConvRate.thr = 0.2)
#'
# sampleSheet = "/g/krebs/barzaghi/HTS/SMF/MM/2021-03-09-HKNVCBBXY/aln_mrg_ddup/QuasR_input_aln_dedup_DE_.txt"
# sample = suppressMessages(readr::read_delim(sampleSheet, delim = "\t"))$SampleName
# Tiles = tileGenome(seqlengths(BSgenome.Mmusculus.UCSC.mm10)[19], ntile = 1)
# RegionOfInterest = Tiles[[ceiling(length(Tiles)/2)]]
# genome = BSgenome.Mmusculus.UCSC.mm10
# coverage = 20
# ConvRate.thr = 0.8
# returnSM = TRUE
CallContextMethylation = function(sampleSheet, sample, genome, RegionOfInterest, coverage = 20, ConvRate.thr = 0.8, returnSM = TRUE){

  message("Setting QuasR project")
  QuasRprj = GetQuasRprj(sampleSheet, genome)

  message("Calling methylation at all Cytosines")
  QuasRprj_sample = QuasRprj[unlist(lapply(unique(sample), function(s){grep(s, QuasRprj@alignments$SampleName)}))]
  MethGR = QuasR::qMeth(QuasRprj_sample, mode="allC", query = RegionOfInterest, collapseBySample = TRUE, keepZero = TRUE)

  message("checking if RegionOfInterest contains information at all")
  CoverageCols = grep("_T$", colnames(elementMetadata(MethGR)))
  lapply(CoverageCols, function(i){
    sum(elementMetadata(MethGR)[,i]) > 0
  }) -> Samples_covered
  if (all(!unlist(Samples_covered))){
    message("No bulk methylation info found for the given RegionOfInterest for any of the samples")
    MethGR = MethGR[elementMetadata(MethGR)[,1]!=0]
    return(MethGR) # ignoring MethSM here since it would be empty anyway
  }

  message("Discard immediately the cytosines not covered in any sample")
  CsToKeep = rowSums(as.matrix(elementMetadata(MethGR)[,CoverageCols])) > 0
  MethGR = MethGR[CsToKeep]

  if (returnSM){
    MethSM = GetSingleMolMethMat(QuasRprj, RegionOfInterest, sample)
    MethSM = lapply(seq_along(unique(sample)), function(i){
      FilterByConversionRate(MethSM[[i]], chr = seqnames(RegionOfInterest), genome = genome, thr = ConvRate.thr)})
  }
  
  message("Subsetting Cytosines by permissive genomic context (GC, HCG)") # Here we use a permissive context: needed for the strand collapsing
  ContextFilteredMethGR = list(GC = FilterContextCytosines(MethGR, genome, "GC"),
                               CG = FilterContextCytosines(MethGR, genome, "HCG"))
  if (returnSM){
    ContextFilteredMethSM = lapply(seq_along(MethSM),
                                   function(n){lapply(seq_along(ContextFilteredMethGR),
                                                      function(i){MethSM[[n]][,colnames(MethSM[[n]]) %in% as.character(start(ContextFilteredMethGR[[i]])), drop=FALSE]})})
  }
  
  message("Collapsing strands")
  StrandCollapsedMethGR = list(GC = CollapseStrands(MethGR = ContextFilteredMethGR[[1]], context = "GC"),
                               CG = CollapseStrands(MethGR = ContextFilteredMethGR[[2]], context = "HCG"))
  if (returnSM){
    StrandCollapsedMethSM = lapply(seq_along(ContextFilteredMethSM),
                                   function(n){
                                     list(GC = CollapseStrandsSM(ContextFilteredMethSM[[n]][[1]], context = "GC", genome = genome, chr = as.character(seqnames(RegionOfInterest))),
                                          CG = CollapseStrandsSM(ContextFilteredMethSM[[n]][[2]], context = "HCG", genome = genome, chr = as.character(seqnames(RegionOfInterest))))})
  }
  
  message("Filtering Cs for coverage")
  CoverageFilteredMethGR = list(GC = CoverageFilter(MethGR = StrandCollapsedMethGR[[1]], thr = coverage),
                                CG = CoverageFilter(MethGR = StrandCollapsedMethGR[[2]], thr = coverage))
  if (returnSM){
    CoverageFilteredMethSM = lapply(seq_along(StrandCollapsedMethSM),
                                    function(n){lapply(seq_along(CoverageFilteredMethGR),
                                                       function(i){
                                                         CsCoveredEnough = as.character(start(CoverageFilteredMethGR[[i]]))[
                                                           !is.na(elementMetadata(CoverageFilteredMethGR[[i]])[,grep("_Coverage$", colnames(elementMetadata(CoverageFilteredMethGR[[i]])))[n]])]
                                                         StrandCollapsedMethSM[[n]][[i]][,colnames(StrandCollapsedMethSM[[n]][[i]]) %in% CsCoveredEnough, drop=FALSE]
                                                       })})
    }

  # Determining stric context based on ExpType
  ExpType = DetectExperimentType(sample)
  if (ExpType == "NO"){
    ExpType_contexts = c("DGCHN", "NWCGW")
  } else if (ExpType == "SS"){
    ExpType_contexts = c("", "CG")
  } else if (ExpType == "DE"){
    ExpType_contexts = c("GC", "HCG") # GCGs will go with GCs.
  }

  message(paste0("Subsetting Cytosines by strict genomic context (", ExpType_contexts[1], ", ", ExpType_contexts[2],") based on the detected experiment type: ", ExpType))
  ContextFilteredMethGR_strict = list(FilterContextCytosines(CoverageFilteredMethGR[[1]], genome, ExpType_contexts[1]),
                                      FilterContextCytosines(CoverageFilteredMethGR[[2]], genome, ExpType_contexts[2]))
  names(ContextFilteredMethGR_strict) = ExpType_contexts
  if (returnSM){
    ContextFilteredMethSM_strict = lapply(seq_along(CoverageFilteredMethSM),
                                          function(n){lapply(seq_along(ContextFilteredMethGR_strict),
                                                             function(i){CoverageFilteredMethSM[[n]][[i]][,colnames(CoverageFilteredMethSM[[n]][[i]]) %in% as.character(start(ContextFilteredMethGR_strict[[i]])), drop=FALSE]})})
  }

  if (ExpType == "DE"){
    message("Merging matrixes")
    MergedGR = sort(append(ContextFilteredMethGR_strict[[1]], ContextFilteredMethGR_strict[[2]]))
    if (returnSM){
      MergedSM = lapply(seq_along(ContextFilteredMethSM_strict), function(n){MergeMatrixes(ContextFilteredMethSM_strict[[n]])})
      }
  } else {
    message("Returning non merged matrixes")
    MergedGR = ContextFilteredMethGR_strict
    if (returnSM){
      MergedSM = ContextFilteredMethSM_strict
      for (i in seq_along(MergedSM)){
        names(MergedSM[[i]]) = ExpType_contexts
        }
      }
  }

  if (returnSM){
    names(MergedSM) = unique(QuasRprj_sample@alignments$SampleName)
    return(list(MergedGR, MergedSM))
  } else {
    return(MergedGR)
  }

}
