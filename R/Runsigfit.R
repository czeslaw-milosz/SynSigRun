#' Install sigfit from GitHub,
#' and its dependent package, rstan.
#'
#' @keywords internal
Installsigfit <- function(){
  message("Installing sigfit from GitHub kgori/sigfit ...\n")
  remotes::install_github(
    "kgori/sigfit",
    args = "--preclean",
    build_vignettes = TRUE)
  # Install package rstan, which is required in the run.
  if (!requireNamespace("rstan", quietly = TRUE)) {
    utils::install.packages(
      "rstan", repos = "https://cloud.r-project.org/",
      dependencies = TRUE)
  }
}


#' Run sigfit attribution on a spectra catalog file
#' and known signatures.
#'
#' @param input.catalog File containing input spectra catalog.
#' Columns are samples (tumors), rows are mutation types.
#'
#' @param gt.sigs.file File containing input mutational signatures.
#' Columns are signatures, rows are mutation types.
#'
#' @param out.dir Directory that will be created for the output;
#' abort if it already exits.  Log files will be in
#' \code{paste0(out.dir, "/tmp")}.
#'
#' @param model Algorithm to be used to extract signatures and
#' attribute exposures. Only "nmf" or "emu" is valid.
#' Default: "nmf".
#'
#' @param seedNumber Specify the pseudo-random seed number
#' used to run sigfit. Setting seed can make the
#' attribution of sigfit repeatable.
#' Default: 1.
#'
#' @param test.only If TRUE, only analyze the first 10 columns
#' read in from \code{input.catalog}.
#' Default: FALSE
#'
#' @param overwrite If TRUE, overwrite existing output.
#' Default: FALSE
#'
#' @return The inferred exposure of \code{sigfit}, invisibly.
#'
#' @details Creates several
#'  files in \code{paste0(out.dir, "/sa.output.rdata")}. These are
#'  TODO(Steve): list the files
#'
#' @importFrom utils capture.output
#'
#' @export
#'
RunsigfitAttributeOnly <-
  function(input.catalog,
           gt.sigs.file,
           out.dir,
           model = "nmf",
           seedNumber = 1,
           test.only = FALSE,
           overwrite = FALSE) {

    # Install MutationalPatterns, if failed to be loaded
    if (!requireNamespace("sigfit", quietly = TRUE)) {
      Installsigfit()
    }

    # Set seed
    set.seed(seedNumber)
    seedInUse <- .Random.seed  # Save the seed used so that we can restore the pseudorandom series
    RNGInUse <- RNGkind() # Save the random number generator (RNG) used


    # Read in spectra data from input.catalog file
    # spectra: spectra data.frame in ICAMS format
    spectra <- ICAMS::ReadCatalog(input.catalog,
                                     strict = FALSE)
    if (test.only) spectra <- spectra[ , 1:10]

    # Remove the catalog related attributes in convSpectra
    convSpectra <- spectra
    class(convSpectra) <- "matrix"
    attr(convSpectra,"catalog.type") <- NULL
    attr(convSpectra,"region") <- NULL
    dimnames(convSpectra) <- dimnames(spectra)
    convSpectra <- t(convSpectra)

    # Read in ground-truth signature file
    gtSignatures <- ICAMS::ReadCatalog(gt.sigs.file)
    # Remove the catalog related attributes in gtSignatures
    tmp <- dimnames(gtSignatures)
    class(gtSignatures) <- "matrix"
    attr(gtSignatures,"catalog.type") <- NULL
    attr(gtSignatures,"region") <- NULL
    dimnames(gtSignatures) <- tmp
    convGtSigs <- t(gtSignatures)

    # Create output directory
    if (dir.exists(out.dir)) {
      if (!overwrite) stop(out.dir, " already exits")
    } else {
      dir.create(out.dir, recursive = T)
    }



    # Derive exposure count attribution results.
    mcmc_samples_fit <- sigfit::fit_signatures(counts = convSpectra,
                                               signatures = convGtSigs,
                                               model = model,
                                               iter = 2000,
                                               warmup = 1000,
                                               chains = 1,
                                               seed = seedNumber)

    # exposuresObj$mean contain the mean of inferred exposures across multiple
    # MCMC samples. Note that inferred exposure in exposuresObj$mean are un-normalized.
    exposuresObj <- sigfit::retrieve_pars(mcmc_samples_fit,
                                          par = "exposures",
                                          hpd_prob = 0.90)


    # mutation count of each tumor
    sum_mutation_count <- rowSums(convSpectra)
    # Multiply relative exposure with total mutation count of each tumor
    exposureCounts <- exposuresObj$mean * sum_mutation_count # i-th row will be multiplied by i-th element (row) of sum_mutation_count

    # Change signature names for exposure matrix exposureCounts:
    # E.g., replace "Signature A" with "sigfit.A".
    colnames(exposureCounts) <-
      gsub(pattern = "Signature ",replacement = "sigfit.",colnames(exposureCounts))



    # Write exposure counts in ICAMS and SynSig format.
    exposureCounts <- t(exposureCounts)
    SynSigGen::WriteExposure(exposureCounts,
                  paste0(out.dir,"/inferred.exposures.csv"))

    # Copy ground.truth.sigs to out.dir
    file.copy(from = gt.sigs.file,
              to = paste0(out.dir,"/ground.truth.signatures.csv"),
              overwrite = overwrite)

    # Save seeds and session information
    # for better reproducibility
    capture.output(sessionInfo(), file = paste0(out.dir,"/sessionInfo.txt")) # Save session info
    write(x = seedInUse, file = paste0(out.dir,"/seedInUse.txt")) # Save seed in use to a text file
    write(x = RNGInUse, file = paste0(out.dir,"/RNGInUse.txt")) # Save seed in use to a text file

    # Return inferred exposures
    invisible(exposureCounts)
  }



#' Run sigfit extraction and attribution on a spectra catalog file
#'
#' WARNING: sigfit can only do exposure attribution
#' using SBS96 spectra catalog and signature catalog!
#'
#' @param input.catalog File containing input spectra catalog.
#' Columns are samples (tumors), rows are mutation types.
#'
#' @param out.dir Directory that will be created for the output;
#' abort if it already exits.  Log files will be in
#' \code{paste0(out.dir, "/tmp")}.
#'
#' @param model Algorithm to be used to extract signatures and
#' attribute exposures. Only "nmf" or "emu" is valid.
#' Default: "nmf".
#'
#' @param CPU.cores Number of CPUs to use in running
#' sigfit. For a server, 30 cores would be a good
#' choice; while for a PC, you may only choose 2-4 cores.
#' By default (CPU.cores = NULL), the CPU.cores would be equal
#' to \code{(parallel::detectCores())/2}, total number of CPUs
#' divided by 2.
#'
#' @param seedNumber Specify the pseudo-random seed number
#' used to run sigfit. Setting seed can make the
#' attribution of sigfit repeatable.
#' Default: 1.
#'
#' @param K.exact,K.range \code{K.exact} is the exact value for
#' the number of signatures active in spectra (K).
#' Specify \code{K.exact} if you know exactly how many signatures
#' are active in the \code{input.catalog}, which is the
#' \code{ICAMS}-formatted spectra file.
#'
#' \code{K.range} is A numeric vector \code{(K.min,K.max)}
#' of length 2 which tell sigfit to search the best
#' signature number active in spectra, K, in this range of Ks.
#' Specify \code{K.range} if you don't know how many signatures
#' are active in the \code{input.catalog}.
#' K.max - K.min >= 3, otherwise an error will be thrown.
#'
#' WARNING: You must specify only one of \code{K.exact} or \code{K.range}!
#'
#' Default: NULL
#'
#' @param test.only If TRUE, only analyze the first 10 columns
#' read in from \code{input.catalog}.
#' Default: FALSE
#'
#' @param overwrite If TRUE, overwrite existing output.
#' Default: FALSE
#'
#' @return The inferred exposure of \code{sigfit}, invisibly.
#'
#' @details Creates several
#'  files in \code{out.dir}. These are:
#'  TODO(Steve): list the files
#'
#'  TODO(Wuyang)
#'
#' @importFrom utils capture.output
#'
#' @export

Runsigfit <-
  function(input.catalog,
           out.dir,
           model = "nmf",
           CPU.cores = NULL,
           seedNumber = 1,
           K.exact = NULL,
           K.range = NULL,
           test.only = FALSE,
           overwrite = FALSE) {

    # Check whether ONLY ONE of K or K.range is specified.
    bool1 <- is.numeric(K.exact) & is.null(K.range)
    bool2 <- is.null(K.exact) & is.numeric(K.range) & length(K.range) == 2
    stopifnot(bool1 | bool2)

    # Check if model parameter is correctly set
    stopifnot(model %in% c("nmf","emu"))


    # Install sigfit, if failed to be loaded
    if (!requireNamespace("sigfit", quietly = TRUE)) {
      Installsigfit()
    }

    # Set seed
    set.seed(seedNumber)
    seedInUse <- .Random.seed  # Save the seed used so that we can restore the pseudorandom series
    RNGInUse <- RNGkind() # Save the random number generator (RNG) used


    # Read in spectra data from input.catalog file
    # spectra: spectra data.frame in ICAMS format
    spectra <- ICAMS::ReadCatalog(input.catalog,
                                  strict = FALSE)
    if (test.only) spectra <- spectra[ , 1:10]

    # Create output directory
    if (dir.exists(out.dir)) {
      if (!overwrite) stop(out.dir, " already exits")
    } else {
      dir.create(out.dir, recursive = T)
    }

    # CPU.cores specifies number of CPU cores to use.
    # CPU.cores will be capped at 30.
    # If CPU.cores is not specified, CPU.cores will
    # be equal to the minimum of 30 or (total cores)/2
    if(is.null(CPU.cores)){
      CPU.cores = min(30,(parallel::detectCores())/2)
    } else {
      stopifnot(is.numeric(CPU.cores))
    }

    # convSpectra: convert the ICAMS-formatted spectra catalog
    # into a matrix which sigfit accepts:
    # 1. Remove the catalog related attributes in convSpectra
    # 2. Transpose the catalog

    convSpectra <- spectra
    class(convSpectra) <- "matrix"
    attr(convSpectra,"catalog.type") <- NULL
    attr(convSpectra,"region") <- NULL
    dimnames(convSpectra) <- dimnames(spectra)
    sample.number <- dim(spectra)[2]
    convSpectra <- t(convSpectra)

    # Determine the best number of signatures (K.best).
    # If K.exact is provided, use K.exact as the K.best.
    # If K.range is provided, determine K.best by doing raw extraction.
    if(bool1){
      K.best <- K.exact
      print(paste0("Assuming there are ",K.best," signatures active in input spectra."))
    }
    if(bool2){

      # Choose the best signature number (K.best) active in the spectra
      # catalog (input.catalog).
      # Raw extraction: estimate most likely number of signatures
      # (Nsig.max + 1) number of elements in mcmc_samples_extr
      # The first Nsig.min number of elements are NULL elements
      # Nsig.min+1 to Nsig.max elements are list elements of two elements: $data and $result
      # The last element is the best signature number
      K.range <- seq.int(K.range[1],K.range[2])

      grDevices::pdf(paste0(out.dir,"/sigfit.find.bestK.pdf"))
      mcmc_samples_extr <-
        sigfit::extract_signatures(counts = convSpectra,   # The spectra matrix required in signature extraction
                                   nsignatures = K.range,  # The possible number of signatures a spectra may have.
                                   model = model,          # Method to use: we choose "nmf" by default. We can also choose "emu"
                                   iter = 1000,            # Number of iterations in the run
                                   seed = seedNumber,
                                   # Number of CPU cores. Pass to sampling function
                                   # rstan::sampling() called by sifit::fit_signatures
                                   cores = CPU.cores)
      grDevices::dev.off()
      K.best <- mcmc_samples_extr$best # Choose K.best
      print(paste0("The best number of signatures is found.",
                   "It equals to: ",K.best))

      # Remove the raw extraction object,
      # which is extremely large (~32G)
      rm(mcmc_samples_extr)
      gc() # Do garbage collection to recycle RAM
    }


    # Precise extraction:
    # Specifying number of signatures, and iterating more times to get more precise extraction
    # Return a list with two elements: $data and $result
    grDevices::pdf(paste0(out.dir,"/sigfit.precise.extraction.pdf"))
    mcmc_samples_extr_precise <-
      sigfit::extract_signatures(counts = convSpectra,   # The spectra matrix required in signature extraction
                                 nsignatures = K.best,   # The possible number of signatures a spectra may have.
                                 model = model,          # Method to use: we choose "nmf" by default. We can also choose "emu"
                                 iter = 5000,            # Number of iterations in the run
                                 seed = seedNumber,
                                 # Number of CPU cores. Pass to sampling function
                                 # rstan::sampling() called by sifit::fit_signatures
                                 cores = CPU.cores)
    grDevices::dev.off()

    extrSigsObject <- sigfit::retrieve_pars(mcmc_samples_extr_precise,
                                            par = "signatures")
    # Fetch mean extracted signatures
    extractedSignatures <- t(extrSigsObject$mean)
    # When catalog is a SBS96 or SBS192 catalog,
    # sigfit will change the names of the channels.
    # The names of channels need to be recovered to ICAMS format.
    rownames(extractedSignatures) <- rownames(spectra)

    # Change signature names for signature matrix extractedSignatures:
    # E.g., replace "Signature A" with "sigfit.A".
    colnames(extractedSignatures) <-
      gsub(pattern = "Signature ",replacement = "sigfit.",colnames(extractedSignatures))
    extractedSignatures <- ICAMS::as.catalog(extractedSignatures,
                                             region = "unknown",
                                             catalog.type = "counts.signature")

    # Write extracted signatures into a ICAMS signature catalog file.
    ICAMS::WriteCatalog(extractedSignatures,
                           paste0(out.dir,"/extracted.signatures.csv"))


    # Derive exposure count attribution results.
    # WARNING: sigfit can only do exposure attribution
    # using SBS96 spectra catalog and signature catalog!
    mcmc_samples_fit <- sigfit::fit_signatures(counts = convSpectra,
                                               signatures = extrSigsObject$mean,
                                               model = model,
                                               iter = 2000,
                                               warmup = 1000,
                                               chains = 1,
                                               seed = 1,
                                               # Number of CPU cores. Pass to sampling function
                                               # rstan::sampling() called by sifit::fit_signatures
                                               cores = CPU.cores)

    # exposuresObj$mean contain the mean of inferred exposures across multiple
    # MCMC samples. Note that inferred exposure in exposuresObj$mean are un-normalized.
    exposuresObj <- sigfit::retrieve_pars(mcmc_samples_fit,
                                          par = "exposures",
                                          hpd_prob = 0.90)


    # mutation count of each tumor
    sum_mutation_count <- rowSums(convSpectra)
    # Multiply relative exposure with total mutation count of each tumor
    exposureCounts <- exposuresObj$mean * sum_mutation_count # i-th row will be multiplied by i-th element (row) of sum_mutation_count

    # Change signature names for exposure matrix exposureCounts:
    # E.g., replace "Signature A" with "sigfit.A".
    colnames(exposureCounts) <-
      gsub(pattern = "Signature ",replacement = "sigfit.",colnames(exposureCounts))

    # Write inferred exposures into a SynSig formatted exposure file.
    exposureCounts <- t(exposureCounts)
    SynSigGen::WriteExposure(exposureCounts,
                  paste0(out.dir,"/inferred.exposures.csv"))


    # Save seeds and session information
    # for better reproducibility
    capture.output(sessionInfo(), file = paste0(out.dir,"/sessionInfo.txt")) # Save session info
    write(x = seedInUse, file = paste0(out.dir,"/seedInUse.txt")) # Save seed in use to a text file
    write(x = RNGInUse, file = paste0(out.dir,"/RNGInUse.txt")) # Save seed in use to a text file

    # Return a list of signatures and exposures
    invisible(list("signature" = extractedSignatures,
                   "exposure" = exposureCounts))
  }
