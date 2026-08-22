.orderable_column <- function(value) {
    if (is.list(value)) {
        return(vapply(
            value,
            function(item) paste(capture.output(dput(item)), collapse = ""),
            character(1)))
    }
    if (inherits(value, "POSIXt")) {
        return(format(value, "%Y-%m-%dT%H:%M:%OS6Z", tz = "UTC"))
    }
    as.character(value)
}

normalize_frame <- function(x, columns, frame_name) {
    if (!is.data.frame(x)) {
        stop("Differential envelope '", frame_name,
             "' must be a data frame.", call. = FALSE)
    }
    if (anyDuplicated(columns)) {
        stop("Differential envelope '", frame_name,
             "' declares duplicate columns.", call. = FALSE)
    }
    missing <- setdiff(columns, names(x))
    if (length(missing)) {
        stop("Differential envelope '", frame_name,
             "' is missing required column(s): ",
             paste(missing, collapse = ", "), ".", call. = FALSE)
    }

    out <- as.data.frame(x[columns], stringsAsFactors = FALSE)
    if (nrow(out)) {
        keys <- lapply(out, .orderable_column)
        keys <- lapply(keys, function(value) {
            value[is.na(value)] <- "<NA>"
            value
        })
        row_order <- do.call(order, c(keys, list(method = "radix")))
        out <- out[row_order, , drop = FALSE]
    }
    rownames(out) <- NULL
    out
}

assert_normalizer_contract <- function() {
    probe <- try(
        normalize_frame(
            data.frame(actual = 1),
            columns = "declared",
            frame_name = "self-check"),
        silent = TRUE)
    if (!inherits(probe, "try-error")) {
        stop("Differential normalization must fail on a missing declared column.",
             call. = FALSE)
    }
    invisible(TRUE)
}

public_envelope <- function(run, value_columns, evidence_columns = character()) {
    required_components <- c("values", "channel_status", "evidence")
    missing_components <- setdiff(required_components, names(run))
    if (length(missing_components)) {
        stop("Differential run is missing public component(s): ",
             paste(missing_components, collapse = ", "), ".", call. = FALSE)
    }

    grain_keys <- intersect(c("PATID", "EVTID", "ELTID"), names(run$values))
    if (!length(grain_keys)) {
        stop("Differential values expose no public grain key.", call. = FALSE)
    }

    list(
        values = normalize_frame(
            run$values,
            unique(c(grain_keys, "variable", value_columns)),
            "values"),
        channel_status = normalize_frame(
            run$channel_status,
            c(grain_keys, "variable", "channel", "source",
              "selection_status", "processing_status"),
            "channel_status"),
        evidence = normalize_frame(
            run$evidence,
            unique(c(grain_keys, "variable", "channel", "source",
                     "evidence_ref", "evidence_kind", evidence_columns)),
            "evidence"))
}
