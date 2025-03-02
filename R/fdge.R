#' Peform a differential expression analysis.
#'
#' Use [flm_def()] to define the design matrix and contrast to test and
#' pass the `FacileLinearModelDefinition` object returned from that to `fdge()`
#' to run the desired differential testing framework (dictated by the `method`
#' parameter) over the data. `flm_def` accepts a
#'
#' @section Differential Expression Testing Methods:
#' The appropriate statistical framework to use for differential expression
#' testing is defined by the type of data that is recorded in the assay
#' `assay_name`, ie. `assay_info(x, assay_name)$assay_type`.
#'
#' The `fdge_methods()` function returns a tibble of appropriate
#' `assay_type -> dge_method` associations. The first entry for each
#' `dge_method` is the default `method` used if one isn't provided by the
#' caller.
#'
#' The available methods are:
#'
#' * `"voom"`: For count data, uses [limma::voomWithQualityWeights()] when
#'   `with_sample_weights = TRUE`.
#' * `"edgeR-qlf"`: The edgeR quasi-likelihood method, for count data.
#' * `"limma-trend"`: Usable for log-transformed data that "looks like" it came
#'    from count data, or where there is a "trend" of the variance with the
#'    mean, uses  [lima::arrayWeights()] when `with_sample_weights = TRUE`.
#' * `"limma"`: Straightup limma, this expects log2-normal like data, with
#'    (largely) no trend of the variance to the mean worth modeling. Uses
#'    [lima::arrayWeights()] when `with_sample_weights = TRUE`
#'
#' @section Feature Filtering Strategy:
#' You will almost always want to filter out lowly abundant features before
#' performing differential expression analysis. For this reason, when the
#' `filter` parameter is set to `"default"`, the filtering strategy is largely
#' is largely based on the logic found in [edgeR::filterByExpr()].
#'
#' When `fdge` analysis is perfomd on count data, the filtering is precisely
#' perfomed by this function, using `design(x)` as the design paratmer to
#' `filterByExpr`. You can modify the filtering behavior by passing any
#' named parameters found in the [edgeR::filterByExpr()] function down to it via
#' `fdge`'s `...` parameter (don't pass `design`, as this is already defined).
#'
#' There are times when you want to tweak this behavior in ways that aren't
#' exactly supported by `filterByExpr`. You can pass in a "feature descriptor"
#' (a character vector of feature ids, or a data.frame with a "feature_id"
#' column) into the following parameters:
#'
#' * `filter_universe`: The features enumerated in this parameter will restrict
#'   the universe of features that can potentially be included in the downstream
#'   analysis. The `filterByExpr()` logic will happen downstream of this
#'   universe. The default value is `NULL`, which specifies the universe of
#'   features to be all of the ones measured using this assay.
#' * `filter_require`: The `filterByExpr` logic happens first on the universe
#'   of features as parameterized. All features enumerated here will be forcibly
#'   included in the analysis, regardless of their expression levels. The
#'   defalut value is `NULL`, which means no genes will be "recovered" if they
#'   don't pass "filter muster".
#' * `filter`: If a feature descriptor is provided here, then only the features
#'   enumerated here (that were assayed) will be included in the analysis.
#'
#' @export
#' @importFrom multiGSEA calculateIndividualLogFC logFC multiGSEA
#'
#' @param x a data source
#' @param assay_name the name of the assay that holds the measurements for test.
#'   Defaults to `default_assay(x)`.
#' @param method The differential testing framework to use over the data. The
#'   valid choices are defined by the type of assay `assay_name`is. Refer to the
#'   *Differential Expression Testing Methods* section for more details.
#' @param filter,with_sample_weights Passed into [biocbox()] to determine which
#'   features (genes) are removed from the dataset for testing, as well as if
#'   to use [limma::arrayWeights()] or [limma::voomWithQualityWeights()]
#'   (where appropriate) when testing (default is not to).
#' @examples
#' efds <- FacileData::exampleFacileDataSet()
#' samples <- FacileData::filter_samples(efds, indication == "BLCA")
#' samples <- samples %>%
#'   mutate(something = sample(c("a", "b"), nrow(samples), replace = TRUE))
#' mdef <- flm_def(samples, covariate = "sample_type",
#'                        numer = "tumor", denom = "normal",
#'                        batch = "sex")
#' dge <- fdge(mdef, method = "voom")
#' if (interactive()) {
#'   viz(dge)
#'   viz(dge, "146909")
#'   shine(dge)
#' }
#' dge.stats <- tidy(dge)
#' dge.sig <- signature(dge)
#'
#' stage.anova <- samples %>%
#'   flm_def(covariate = "stage", batch = "sex") %>%
#'   fdge(method = "voom")
#' anova.sig <- signature(stage.anova)
fdge <- function(x, ..., verbose = FALSE) {
  UseMethod("fdge", x)
}

#' @export
#' @rdname fdge
fdge.FacileAnovaModelDefinition <- function(x, assay_name = NULL, method = NULL,
                                            filter = "default",
                                            with_sample_weights = FALSE, ...,
                                            verbose = FALSE) {
  res <- NextMethod(coef = x$coef)
  res
}

#' @export
fdge.FacileTtestDGEModelDefinition <- function(x, assay_name = NULL,
                                               method = NULL,
                                               filter = "default",
                                               with_sample_weights = FALSE,
                                               treat_lfc = NULL,
                                               ..., verbose = FALSE) {
  res <- NextMethod(contrast = x$contrast)
  res
}

#' @export
#' @rdname fdge
#' @param ... passed down into inner methods, such as `biocbox` to tweak
#'   filtering criteria, for instance
fdge.FacileLinearModelDefinition <- function(x, assay_name = NULL, method = NULL,
                                             filter = "default",
                                             with_sample_weights = FALSE,
                                             treat_lfc = NULL,
                                             ..., verbose = FALSE) {
  messages <- character()
  warnings <- character()
  errors <- character()
  .fds <- assert_facile_data_store(fds(x))

  if (is.ttest(x)) {
    testme <- x[["contrast"]]
    clazz <- "FacileTtestAnalysisResult"
  } else {
    testme <- x[["coef"]]
    clazz <- "FacileAnovaAnalysisResult"
  }

  if (is.null(assay_name)) assay_name <- default_assay(.fds)
  ainfo <- try(assay_info(.fds, assay_name), silent = TRUE)
  if (is(ainfo, "try-error")) {
    msg <- glue("assay_name `{assay_name}` not present in FacileDataStore")
    errors <- c(errors, msg)
    assay_type <- "ERROR"
  } else {
    assay_type <- ainfo$assay_type
  }

  dge_methods <- fdge_methods(assay_type)
  if (nrow(dge_methods) == 0L) {
    msg <- glue("Differential expression method `{method}` for assay_type ",
                "`{assay_type}` not found")
    errors <- c(errors, msg)
  }

  if (length(errors) == 0L) {
    if (verbose) {
      message("... retrieving expression data")
    }
    bb <- biocbox(x, assay_name, method, dge_methods, filter,
                  with_sample_weights = with_sample_weights, ...)
    messages <- c(messages, bb[["messages"]])
    warnings <- c(warnings, bb[["warnings"]])
    errors <- c(errors, bb[["errors"]])

    method <- bb[["dge_method"]]

    if (!is.null(treat_lfc)) {
      if (!test_number(treat_lfc, lower = 0) || !is.ttest(x)) {
        warnings <- c(
          warnings,
          "Illegal parameter passed to `treat_lfc`. It is being ignored")
        treat_lfc <- 0
      }
    } else {
      treat_lfc <- 0
    }
    use.treat <- treat_lfc > 0
    y <- result(bb)
    des <- design(bb)

    if (verbose) {
      message("... running differential expression analysis")
    }
    result <- calculateIndividualLogFC(y, des, contrast = testme,
                                       treat.lfc = treat_lfc)
    # multiGSEA::calculateIndividualLogFC returns the stats table ordered by
    # featureId, let's put the features back in the order they are in y
    rownames(result) <- result[["featureId"]]
    result <- result[rownames(y),]

    axe.cols <- c("featureId", "x.idx")
    if (is(y, "DGEList")) {
      axe.cols <- c(axe.cols, "t")
    }
    for (col in axe.cols) {
      if (col %in% names(result)) result[[col]] <- NULL
    }
    result <- as.tbl(result)
  } else {
    result <- NULL
  }

  # Hack here to support call from a bioc-container that we haven't turned
  # into a facile data store yet
  if (!is.null(result) && !"feature_type" %in% colnames(result)) {
    feature_type <- guess_feature_type(result[["feature_id"]], summarize = TRUE)
    result[["feature_type"]] <- feature_type[["feature_type"]]
    result <- select(result, feature_type, everything())
  }

  # We'll stick on the lib.size and norm.factors on these samples so that
  # downstream queries over this result will use the same normalization factors
  # when retrieving data as well.
  if (is(y, "DGEList") || is(y, "EList")) {
    samples. <- samples(x)
    sinfo <- if (is(y, "DGEList")) y[["samples"]] else y[["targets"]]
    for (cname in c("lib.size", "norm.factors")) {
      if (cname %in% colnames(sinfo) && is.numeric(sinfo[[cname]])) {
        samples.[[cname]] <- sinfo[[cname]]
      }
    }
    x[["covariates"]] <- samples. # `samples(x) <- samples.` would be nice!
  }

  out <- list(
    result = result,
    params = list(
      assay_name = assay_name,
      method = bb[["dge_method"]],
      model_def = x,
      treat_lfc = if (use.treat) treat_lfc else NULL,
      with_sample_weights = with_sample_weights),
    # Standard FacileAnalysisResult things
    fds = .fds,
    messages = messages,
    warnings = warnings,
    errors = errors)

  class(out) <- c(clazz, "FacileDgeAnalysisResult", "FacileAnalysisResult")
  out
}

# Methods and Accessors ========================================================

#' @noRd
#' @export
result.FacileDgeAnalysisResult <- function(x, name = "result", ...) {
  tidy(x, name, ...)
}

tidy.FacileDgeAnalysisResult <- function(x, name = "result", ...) {
  x[["result"]]
}

#' @noRd
#' @export
initialized.FacileDgeAnalysisResult <- function(x, ...) {
  stat.table <- tidy(x)
  is.data.frame(stat.table) &&
    is.numeric(stat.table[["pval"]]) &&
    is.numeric(stat.table[["padj"]])
}

#' @noRd
#' @export
features.FacileDgeAnalysisResult <- function(x, ...) {
  stat.table <- tidy(x)
  take <- c("feature_id", "feature_type", "symbol", "assay", "assay_type")
  take <- intersect(take, colnames(stat.table))
  select(stat.table, !!take, everything())
}

#' @noRd
#' @export
model.FacileDgeAnalysisResult <- function(x, ...) {
  param(x, "model_def")
}

#' @noRd
#' @export
design.FacileDgeAnalysisResult <- function(x, ...) {
  design(model(x, ...), ...)
}

#' @noRd
#' @export
name.FacileTtestAnalysisResult <- function(x, ...) {
  m <- model(x)
  covname <- param(m, "covariate")
  batch <- param(m, "batch")
  contrast <- gsub(" ", "", m[["contrast_string"]])
  contrast <- gsub("/", ".divby.", contrast, fixed = TRUE)
  out <- sprintf("%s_%s", covname, contrast)
  if (length(batch)) {
    out <- sprintf("%s_controlfor_%s", out, paste(batch, collapse = ","))
  }
  out
}

#' @noRd
#' @export
label.FacileTtestAnalysisResult <- function(x, ...) {
  m <- model(x)
  covname <- param(m, "covariate")
  batch <- param(m, "batch")
  contrast <- m[["contrast_string"]]
  out <- sprintf("%s: %s", covname, contrast)
  if (length(batch)) {
    out <- sprintf("%s (control for %s)", out, paste(batch, collapse = ","))
  }
  out
}

#' @noRd
#' @export
name.FacileAnovaAnalysisResult <- function(x, ...) {
  m <- model(x)
  covname <- param(m, "covariate")
  clevels <- unique(samples(m)[[covname]])
  batch <- param(m, "batch")
  out <- sprintf("%s_%s", covname, paste(clevels, collapse = ","))
  if (length(batch)) {
    out <- sprintf("%s_controlfor_%s", out, paste(batch, collapse = ","))
  }
  out
}

#' @noRd
#' @export
label.FacileAnovaAnalysisResult <- function(x, ...) {
  m <- model(x)
  covname <- param(m, "covariate")
  clevels <- unique(samples(m)[[covname]])
  batch <- param(m, "batch")
  out <- sprintf("%s [%s]", covname, paste(clevels, collapse = ","))
  if (length(batch)) {
    out <- sprintf("%s (control for %s)", out, paste(batch, collapse = ","))
  }
  out
}

# Ttest Ranks and Signatures ===================================================

#' @export
#' @noRd
ranks.FacileTtestAnalysisResult <- function(x, signed = TRUE, rank_by = "logFC",
                                            ...) {
  ranks. <- tidy(x, ...)
  if (signed) {
    rank_by <- assert_choice(rank_by, colnames(ranks.))
    assert_numeric(ranks.[[rank_by]])
    ranks. <- arrange_at(ranks., rank_by, desc)
  } else {
    ranks. <- arrange(ranks., pval)
  }

  out <- list(
    result = ranks.,
    params = list(signed = signed),
    ranking_columns = "logFC",
    ranking_order = "descending",
    fds = fds(x))

  # FacileTtestFeatureRanksSigned
  clazz <- "Facile%sFeatureRanks%s"
  s <- if (signed) "Signed" else "Unsigned"
  classes <- sprintf(clazz, c("Ttest", "Ttest",  "", ""), c(s, "", s, ""))
  class(out) <- c(classes, "FacileFeatureRanks")
  out
}

#' @export
#' @noRd
signature.FacileTtestAnalysisResult <- function(x, min_logFC = x[["treat_lfc"]],
                                                max_padj = 0.10, ntop = 20,
                                                name = NULL,
                                                collection_name = NULL,
                                                ...) {
  signature(ranks(x, ...), min_logFC = min_logFC, max_padj = max_padj,
            ntop = ntop, name = name, collection_name = collection_name, ...)
}

#' @export
#' @noRd
signature.FacileTtestFeatureRanks <- function(x, min_logFC = x[["treat_lfc"]],
                                              max_padj = 0.10,
                                              ntop = 20,
                                              name = NULL,
                                              collection_name = NULL,
                                              ...) {
  if (is.null(name)) name <- "Ttest signature"
  name. <- assert_string(name)

  if (is.null(collection_name)) collection_name <- class(x)[1L]
  assert_string(collection_name)

  if (is.null(min_logFC)) min_logFC <- 0
  min_logFC <- abs(min_logFC)

  res <- tidy(x) %>%
    mutate(direction = ifelse(logFC > 0, "up", "down"))

  if (signed(x)) {
    up <- res %>%
      filter(padj <= max_padj, logFC > min_logFC) %>%
      head(ntop)
    down <- res %>%
      filter(padj <= max_padj, logFC < -min_logFC) %>%
      tail(ntop)
    sig <- bind_rows(up, down)
  } else {
    sig <- res %>%
      filter(padj <= max_padj) %>%
      head(ntop)
  }

  sig <- sig %>%
    mutate(collection = collection_name, name = paste(name., direction)) %>%
    select(collection, name, feature_id, symbol, direction,
           logFC, pval, padj, everything())

  out <- list(
    result = sig,
    params = list(max_padj = max_padj, min_logFC = min_logFC, ntop = ntop))
  class(out) <- sub("Ranks", "Signature", class(x))
  out
}

# ANOVA Ranks and Signatures ===================================================

#' @noRd
#' @export
ranks.FacileAnovaAnalysisResult <- function(x, signed = FALSE, ...) {
  if (signed) {
    warning("ANOVA results can only provide unsigned ranks ",
            "based on p-value, which is the same as desc(Fstatistic)",
            immediate. = TRUE)
    signed <- FALSE
  }
  ranks. <- arrange(result(x, ...), desc(F))

  out <- list(
    result = ranks.,
    params = list(signed = signed),
    ranking_columns = "F",
    ranking_order = "descending")
  # FacileAnovaFeatureRanksSigned
  clazz <- "Facile%sFeatureRanks%s"
  s <- if (signed) "Signed" else "Unsigned"
  classes <- sprintf(clazz, c("Anova", "Anova",  "", ""), c(s, "", s, ""))
  class(out) <- c(classes, "FacileFeatureRanks")
  out
}

#' @export
#' @noRd
signature.FacileAnovaAnalysisResult <- function(x, max_padj = 0.10, ntop = 20,
                                           name = NULL, collection_name = NULL,
                                           ...) {
  signature(ranks(x, ...), max_padj = max_padj, ntop = ntop, name = name,
            collectoin_name = collection_name, ...)
}

#' @export
#' @noRd
signature.FacileAnovaFeatureRanks <- function(x, max_padj = 0.10,
                                              ntop = 20, name = NULL,
                                              collection_name = NULL,
                                              ...) {
  if (is.null(name)) name <- "Anova signature"
  name. <- assert_string(name)

  if (is.null(collection_name)) collection_name <- class(x)[1L]
  assert_string(collection_name)

  sig <- result(x) %>%
    filter(padj <= max_padj) %>%
    mutate(collection = collection_name, name = name.,
           direction = "udefined") %>%
    head(ntop) %>%
    select(collection, name, feature_id, symbol, direction, F, pval, padj,
           everything())

  out <- list(
    result = sig,
    params = list(ntop = ntop, max_padj = max_padj))
  class(out) <- sub("Ranks$", "Signature", class(x))
  out
}

# Facile API ===================================================================

#' @noRd
#' @export
samples.FacileDgeAnalysisResult <- function(x, ...) {
  samples(model(x), ...)
}

#' @section FacileDgeAnalysisResult:
#' Given a FacileDgeAnalysisResult, we can re-materialize the Bioconductor assay
#' container used within the differential testing pipeline used from [fdge()].
#' Currently we have limited our analysis framework to either work over DGEList
#' (edgeR) or EList (limma) containers.
#'
#' @export
#' @rdname biocbox
biocbox.FacileDgeAnalysisResult <- function(x, ...) {
  res <- biocbox(model(x),
                 x[["params"]][["assay_name"]],
                 x[["params"]][["method"]],
                 filter = result(x)[["feature_id"]], ...)
  res
}

#' @noRd
#' @export
print.FacileDgeAnalysisResult <- function(x, ...) {
  cat(format(x, ...), "\n")
}

format.FacileDgeAnalysisResult <- function(x, ...) {
  test_type <- if (is.ttest(x)) "ttest" else "ANOVA"
  mdef <- model(x)
  des <- design(mdef)
  formula <- mdef[["design_formula"]]

  if (test_type == "ttest") {
    test <- mdef[["contrast_string"]]
    des.cols <- names(mdef$contrast[mdef$contrast != 0])
  } else {
    test <- sprintf("%s (%s)", mdef[["covariate"]],
                    paste(colnames(des)[mdef[["coef"]]], collapse = "|"))
    des.cols <- c(1, mdef$coef)
  }

  # nsamples <- sum(colSums(des[, des.cols, drop = FALSE]) != 0)
  nsamples <- sum(rowSums(des[,des.cols,drop = FALSE]) > 0)

  res <- result(x)
  ntested <- nrow(res)
  nsig <- sum(!is.na(res[["padj"]]) & res[["padj"]] < 0.10)

  out <- paste(
    "===========================================================\n",
    sprintf("FacileDgeAnalysisResult (%s)\n", test_type),
    "-----------------------------------------------------------\n",
    glue("Significant Results (FDR < 0.1): ({nsig} / {ntested})"), "\n",
    "Formula: ", formula, "\n",
    "Tested: ", test, "\n",
    "Number of samples: ", nsamples, "\n",
    "===========================================================\n",
    sep = "")
  out
}


# Helpers ======================================================================

#' A table of assay_type,dge_method combination parameters
#'
#' This table is used to match the assay_type,dge_method combination with
#' the appropriate bioc container class `bioc_class`, and default edgeR/limma
#' model fitting params.
#'
#' @export
#' @param assay_type An optional string specifying the valid dge methods for
#'   a given assay type.
#' @return A tibble of assay_type -> method and parameter associtiations. If
#'   `assay_type`is not `NULL`, this will be filtered to the associations
#'   valid only for that `assay_type`. If none are found, this will be a
#'   0-row tibble.
fdge_methods <- function(assay_type = NULL,
                         on_missing = c("error", "warning")) {
  on_missing <- match.arg(on_missing)
  # assay_type values : rnaseq, umi, affymrna, affymirna, log2

  # This is a table of assay_type : dge_method possibilites. The first row
  # for each assay_type is the default analysis method
  assay_methods <- tribble(
    ~assay_type,   ~dge_method,         ~bioc_class,
    "rnaseq",      "voom",              "EList",
    "rnaseq",      "edgeR-qlf",         "DGEList",
    "rnaseq",      "limma-trend",       "EList",
    "umi",         "voom",              "EList",
    "umi",         "edgeR-qlf",         "DGEList",
    "umi",         "limma-trend",       "EList",
    "tpm",         "limma-trend",       "EList",
    "cpm",         "limma-trend",       "EList",
    "isoseq",      "voom",              "EList",
    "isoseq",      "limma-trend",       "EList",
    "affymrna",    "limma",             "EList",
    "affymirna",   "limma",             "EList",
    "lognorm",     "limma",             "EList",
    "real",        "ranks",             "EList")

  method_params <- tribble(
    ~dge_method,    ~robust_fit,  ~robust_ebayes,  ~trend_ebayes, ~can_sample_weight,
    "voom",         FALSE,        FALSE,           FALSE,          TRUE,
    "edgeR-qlf",    TRUE,         FALSE,           FALSE,          FALSE,
    "limma-trend",  FALSE,        FALSE,           TRUE,           TRUE,
    "limma",        FALSE,        FALSE,           FALSE,          TRUE)

  info <- left_join(assay_methods, method_params, by = "dge_method")

  if (!is.null(assay_type)) {
    if (on_missing == "error") {
      assert_choice(assay_type, info[["assay_type"]])
    }
    info <- info[info[["assay_type"]] == assay_type,]
  }

  info
}
