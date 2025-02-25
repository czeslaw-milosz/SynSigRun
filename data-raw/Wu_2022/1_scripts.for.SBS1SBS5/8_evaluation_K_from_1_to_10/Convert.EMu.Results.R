
## Run 2a_running_approaches_without_knowing_K/Run.EMu.py
## Before running this script.
##
## Run this script before running Summarize.all.results.R



# Set working directory to "<SynSigRun Home>/data-raw/scripts.for.SBS1SBS5"
# before running this script.
# SynSigRun home can be retrieved by usethis::proj_path
#
# PATH <- paste0(usethis::proj_path,"/data-raw/scripts.for.SBS1SBS5")
# setwd(PATH)



## Specify slopes and Rsqs for the datasets
slopes <- c(0.1,0.5,1,2,10)
Rsqs <- c(0.1,0.2,0.3,0.6)
datasetNames <- c()
for(slope in slopes)
  for(Rsq in Rsqs)
    datasetNames <- c(datasetNames, paste0("S.",slope,".Rsq.",Rsq))

## Specify 20 seeds used in software running
seedsInUse <- c(1, 691, 1999, 3511, 8009,
                9902, 10163, 10509, 14476, 20897,
                27847, 34637, 49081, 75679, 103333,
                145879, 200437, 310111, 528401, 1076753)


## After running EMu, convert EMu-formatted tsv files
## to SynSigEval/ICAMS-formatted csv files.
for(datasetName in datasetNames){
  for(nrun in 1:20){
    ## Grep the names of EMu-formatted files.
    ## When the K is different, the output file would be different.
    ## Extracted signature file name:
    ## _{K}_ml_spectra.txt
    ## Attributed exposure file name:
    ## _{K}_assigned.txt
    resultDir <-
      paste0(datasetName,
            "/sp.sp/ExtrAttrFromOne/EMu.results/",
            "run.",nrun,"/")

    files <- list.files(resultDir)

    signatureFile <- files[grep(pattern = "_ml_spectra.txt",x = files)]
    exposureFile <- files[grep(pattern = "_assigned.txt",x = files)]


    ## Convert signatures
    signatures <- SynSigEval::ReadEMuCatalog(
      paste0(resultDir,"/",signatureFile),
      mutTypes = ICAMS::catalog.row.order$SBS96,
      sigOrSampleNames = NULL,
      region = "unknown",
      catalog.type = "counts.signature")
    ## extracted signatures need to be normalized.
    for(sigName in colnames(signatures)){
      signatures[,sigName] <- signatures[,sigName] / sum(signatures[,sigName])
    }
    ICAMS::WriteCatalog(
      signatures,
      paste0(resultDir,"/extracted.signatures.csv"))

    ## Convert exposures
    rawExposure <- SynSigEval::ReadEMuExposureFile(
      exposureFile = paste0(resultDir,"/",exposureFile),
      sigNames = NULL,
      sampleNames = paste0("TwoCorreSigsGen::",1:500))
    ## The sum of exposure of each spectrum needs to
    ## be normalized to the total number of mutations
    ## in each spectrum.
    spectra <- ICAMS::ReadCatalog(
      file = paste0(datasetName,
                    "/sp.sp/ground.truth.syn.catalog.csv"),
      catalog.type = "counts",
      strict = FALSE)
    exposureCounts <- rawExposure
    for(sample in colnames(exposureCounts)){
      exposureCounts[,sample] <- rawExposure[,sample] / sum(rawExposure[,sample]) * sum(spectra[,sample])
    }

    SynSigGen::WriteExposure(
      exposureCounts,
      paste0(resultDir,"/inferred.exposures.csv"))

  }
}
