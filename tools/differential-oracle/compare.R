args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
    stop(
        "Usage: Rscript tools/differential-oracle/compare.R <before.rds> <after.rds>",
        call. = FALSE)
}

before <- readRDS(args[[1]])
after <- readRDS(args[[2]])

if (!is.list(before) || !is.list(after) ||
    !identical(names(before), names(after))) {
    stop("Differential snapshots contain different case names or order.",
         call. = FALSE)
}

for (case_name in names(before)) {
    comparison <- all.equal(
        before[[case_name]],
        after[[case_name]],
        check.attributes = TRUE)
    if (!isTRUE(comparison)) {
        message("DIFF: ", case_name)
        print(comparison)
        quit(status = 1L)
    }
    message("OK: ", case_name)
}
