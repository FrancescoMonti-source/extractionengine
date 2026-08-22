args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
    stop(
        "Usage: Rscript tools/differential-oracle/snapshot.R <repo> <output.rds>",
        call. = FALSE)
}

root <- normalizePath(args[[1]], winslash = "/", mustWork = TRUE)
output <- args[[2]]
if (!grepl("^([A-Za-z]:[/\\\\]|/)", output)) {
    output <- file.path(root, output)
}
output <- normalizePath(output, winslash = "/", mustWork = FALSE)

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_arg) != 1L) {
    stop("Cannot resolve the differential-oracle script directory.",
         call. = FALSE)
}
script_dir <- dirname(normalizePath(
    sub("^--file=", "", script_arg), winslash = "/", mustWork = TRUE))

suppressPackageStartupMessages(pkgload::load_all(root, quiet = TRUE))
oracle <- new.env(parent = globalenv())
sys.source(file.path(script_dir, "normalize.R"), envir = oracle)
sys.source(file.path(script_dir, "fixtures.R"), envir = oracle)
oracle$assert_normalizer_contract()

cases <- oracle$differential_cases()
if (!is.list(cases) || !length(cases) || is.null(names(cases)) ||
    anyNA(names(cases)) || any(!nzchar(names(cases))) ||
    anyDuplicated(names(cases))) {
    stop("Differential cases must be a non-empty uniquely named list.",
         call. = FALSE)
}

snapshot <- lapply(cases, function(case) {
    required <- c("run", "value_columns", "evidence_columns")
    missing <- setdiff(required, names(case))
    if (length(missing)) {
        stop("Differential case is missing field(s): ",
             paste(missing, collapse = ", "), ".", call. = FALSE)
    }
    oracle$public_envelope(
        case$run,
        value_columns = case$value_columns,
        evidence_columns = case$evidence_columns)
})

dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
saveRDS(snapshot, output, version = 3)
message("Wrote ", length(snapshot), " synthetic case(s) to ", output)
