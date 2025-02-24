#' Install deconstructSigs from CRAN
InstalldeconstructSigs <- function(){
  message("Installing deconstructSigs from CRAN...\n")
  utils::install.packages("deconstructSigs")
}

#' Run deconstructSigs attribution on a spectra catalog file
#' and known signatures.
#'
#' @param input.catalog File containing input spectra catalog. Columns are
#' samples (tumors), rows are mutation types.
#'
#' @param gt.sigs.file File containing input mutational signatures. Columns are
#' signatures, rows are mutation types.
#'
#' @param out.dir Directory that will be created for the output;
#' abort if it already exits.  Log files will be in
#' \code{paste0(out.dir, "/tmp")}.
#'
#' @param seedNumber Specify the pseudo-random seed number
#' used to run deconstructSigs. Setting seed can make the
#' attribution of deconstructSigs repeatable.
#' Default: 1.
#'
#' @param test.only If TRUE, only analyze the first 10 columns
#' read in from \code{input.catalog}.
#' Default: FALSE
#'
#' @param overwrite If TRUE, overwrite existing output.
#' Default: FALSE
#'
#' @return The inferred exposure of \code{deconstructSigs}, invisibly.
#'
#' @details Creates several
#'  files in \code{paste0(out.dir, "/sa.output.rdata")}. These are
#'  TODO(Steve): list the files
#'
#' @importFrom utils capture.output
#'
#' @export

RundeconstructSigsAttributeOnly <-
  function(input.catalog,
           gt.sigs.file,
           out.dir,
           seedNumber = 1,
           test.only = FALSE,
           overwrite = FALSE) {

    # Install deconstructSigs, if failed to be loaded
    if (!requireNamespace("deconstructSigs", quietly = TRUE)) {
      InstalldeconstructSigs()
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


    # Read in ground-truth signature file
    # gt.sigs: signature data.frame in ICAMS format
    gtSignatures <- ICAMS::ReadCatalog(gt.sigs.file)

    # Create output directory
    if (dir.exists(out.dir)) {
      if (!overwrite) stop(out.dir, " already exits")
    } else {
      dir.create(out.dir, recursive = T)
    }

    # Convert ICAMS-formatted spectra and signatures
    # into deconstructSigs format
    # Requires removal of redundant attributes.
    convSpectra <- spectra
    attr(convSpectra,"catalog.type") <- NULL
    attr(convSpectra,"region") <- NULL
    class(convSpectra) <- "matrix"
    convSpectra <- as.data.frame(t(convSpectra))

    gtSignaturesDS <- gtSignatures
    attr(gtSignaturesDS,"catalog.type") <- NULL
    attr(gtSignaturesDS,"region") <- NULL
    class(gtSignaturesDS) <- "matrix"
    gtSignaturesDS <- as.data.frame(t(gtSignaturesDS))

    # Obtain inferred exposures using whichSignatures function
    # Note: deconstructSigs::whichSignatures() can only attribute ONE tumor at each run!
    num.tumors <- nrow(convSpectra)
    # In each cycle, obtain inferred exposures for each tumor.
    exposures <- data.frame()

    for(ii in 1:num.tumors){
      output.list <- deconstructSigs::whichSignatures(tumor.ref = convSpectra[ii,,drop = FALSE],
                                                      signatures.ref = gtSignaturesDS,
                                                      contexts.needed = TRUE)
      # names(output.list): [1] "weights" "tumor"   "product" "diff"    "unknown"
      # $weights: inferred signature exposure (in relative percentage)
      # Note: sum of all exposure may be smaller than 1
      # $tumor: input tumor spectrum
      # $product: Reconstructed catalog = product of signatures and exposures
      # = $weights %*% gtSignaturesDS
      # $diff: $product - $tumor
      # $unknown: 100% - $weights
      # (percentage of exposures not inferred by this program)

      # Obtain absolute exposures for current tumor
      exposures.one.tumor <- output.list$weights
      exposures.one.tumor <- exposures.one.tumor * sum(convSpectra[ii,,drop = FALSE])

      # Bind exposures for current tumor to exposure data.frame
      exposures <- rbind(exposures,exposures.one.tumor)
    }



    # Write exposure counts in ICAMS and SynSig format.
    exposureCounts <- t(exposures)
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
