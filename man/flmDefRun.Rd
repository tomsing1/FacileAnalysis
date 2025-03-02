% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/flm_def-shiny.R
\name{flmDefRun}
\alias{flmDefRun}
\title{A shiny module that generates a linear model definition via \code{flm_def}.}
\usage{
flmDefRun(input, output, session, rfds, ..., debug = FALSE,
  .reactive = TRUE)
}
\value{
A \code{ReactiveFacileLinearModelDefinition} object, the output from
\code{\link[=flm_def]{flm_def()}}.
}
\description{
\preformatted{model_info <- fds \%>\%
  filter_samples(indication == "BLCA") \%>\%
  flm_def(covariate = "sample_type", numer = "tumor", denom = "normal",
          batch = "sex")
}
}
