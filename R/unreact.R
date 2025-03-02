#' Replace reactive versions of facile objects with their "inert" counterparts
#'
#' This function is primariy meant to be called within the `frunGadget`
#' framework. We attempt to find all "reactive"-like components and covert them
#' into their "inert" versions so that they can be used in the context of an
#' ongoing analysis outside of the shiny world. This is an important function,
#' but it is purposefully not exported.
#'
#' We are primariy concerned about replacing the `ReactiveFacileDataStore` that
#' is stashed within facile components (`facile_frames`) (set and retrieved with
#' the `set_fds()` and `fds()` setters and getters), with their inner
#' `FacileDataStore`
#'
#' This function needs to be called within the gadget, ie. I'm pretty sure it
#' needs to fire in a reactive environment, which you get in the
#' `observeEvent(intput$done, { ... })` expression.
#'
#' NOTE: I don't want to export this function, or its class-speficic
#' implementation, but when this package is library()/loaded, and one of its
#' functions calls it inernally, for some reason the `unreact.default` function
#' isn't found ...
#'
#' @export
#' @param x stuff and things
#' @return a version of x with an "inert" versions of internal facile-components
#'   (primariy FacileDataStore) wherever they may be.
unreact <- function(x, ...) {
  UseMethod("unreact", x)
}

#' @noRd
#' @export
unreact.default <- function(x, ...) {
  x
}

#' @noRd
#' @export
unreact.list <- function(x, ...) {
  out <- lapply(x, unreact)
  class(out) <- class(x)
  out
}

#' @noRd
#' @export
unreact.FacileAnalysisResult <- function(x, ...) {
  unreact.list(x, ...)
}

#' @noRd
#' @export
unreact.facile_frame <- function(x, ...) {
  out <- as_facile_frame(x, fds(fds(x)))
  class(out) <- rm.rds.class(x)
  out
}


#' @noRd
#' @export
unreact.ReactiveFacileDataStore <- function(x, ...) {
  fds(x)
}

#' @noRd
rm.rds.class <- function(x, ...) {
  oclass <- class(x)
  rds.classes <- grepl("^reactive_", oclass, ignore.case = TRUE)
  oclass[!rds.classes]
}
