% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/RunYAPSAAttributionOnly.R
\name{RunYAPSAAttributeOnly}
\alias{RunYAPSAAttributeOnly}
\title{Run YAPSA attribution on a spectra catalog file
and known signatures.}
\usage{
RunYAPSAAttributeOnly(
  input.catalog,
  gt.sigs.file,
  out.dir,
  seedNumber = 1,
  signature.cutoff = NULL,
  test.only = FALSE,
  overwrite = FALSE
)
}
\arguments{
\item{input.catalog}{File containing input spectra catalog.
Columns are samples (tumors), rows are mutation types.}

\item{gt.sigs.file}{File containing input mutational signatures.
Columns are signatures, rows are mutation types.}

\item{out.dir}{Directory that will be created for the output;
abort if it already exits.  Log files will be in
\code{paste0(out.dir, "/tmp")}.}

\item{seedNumber}{Specify the pseudo-random seed number
used to run YAPSA. Setting seed can make the
attribution of YAPSA repeatable.
Default: 1.}

\item{signature.cutoff}{A numeric vector of values less than 1.
Signatures from within W with an overall exposure
less than the respective value in \code{in_cutoff_vector}
will be discarded.
Default: vector length of number of sigs with all zeros}

\item{test.only}{If TRUE, only analyze the first 10 columns
read in from \code{input.catalog}.
Default: FALSE}

\item{overwrite}{If TRUE, overwrite existing output.
Default: FALSE}
}
\value{
The inferred exposure of \code{YAPSA}, invisibly.
}
\description{
Run YAPSA attribution on a spectra catalog file
and known signatures.
}
\details{
Creates several
 files in \code{paste0(out.dir, "/sa.output.rdata")}. These are
 TODO(Steve): list the files
}
