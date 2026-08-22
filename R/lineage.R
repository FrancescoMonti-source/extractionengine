# Internal activation lineage -------------------------------------------------
#
# One row identifies one activation artifact at one execution stage. The
# relation deliberately carries only coordinates, never source payload. During
# the Phase 4 migration the executors still expose their legacy frames, but
# downstream selection, combine placement, and terminal audit counts read this
# relation instead of reconstructing the same facts independently.

.lineage_stage_order <- c(
    "pre_selector", "window", "selected", "model_input", "used", "cited")
.lineage_selected_stages <- c("selected", "model_input", "used", "cited")
.lineage_model_input_stages <- c("model_input", "cited")
.lineage_contributing_stages <- c("used", "cited")

.empty_activation_lineage <- function() {
    tibble::tibble(
        task_id = character(),
        variable = character(),
        channel = character(),
        source = character(),
        stage = character(),
        artifact_type = character(),
        artifact_id = character(),
        source_row_ref = character(),
        artifact_position = integer(),
        source_PATID = character(),
        source_EVTID = character(),
        source_ELTID = character())
}

.lineage_source_key <- function(rows, key) {
    if (key %in% names(rows)) as.character(rows[[key]]) else
        rep(NA_character_, nrow(rows))
}

.lineage_input_rows <- function(rows, artifact_type) {
    id_column <- switch(
        artifact_type,
        source_row = "source_row_id",
        document = "ELTID",
        stop("Unsupported upstream lineage artifact type: ", artifact_type,
             call. = FALSE))
    required <- c("task_id", id_column)
    missing <- setdiff(required, names(rows))
    if (length(missing)) {
        stop("Upstream lineage rows are missing ",
             paste(missing, collapse = ", "), ".", call. = FALSE)
    }
    columns <- unique(c(required, intersect(.identity_spine, names(rows))))
    dplyr::distinct(tibble::as_tibble(rows)[columns])
}

.lineage_artifact_rows <- function(rows, variable_name, channel_name,
                                   source_name, stage, artifact_type) {
    if (!is.data.frame(rows) || !nrow(rows)) {
        return(.empty_activation_lineage())
    }
    id_column <- switch(
        artifact_type,
        snippet = "snippet_id",
        source_row = "source_row_id",
        document = "ELTID",
        stop("Unsupported lineage artifact type: ", artifact_type,
             call. = FALSE))
    required <- c("task_id", id_column)
    missing <- setdiff(required, names(rows))
    if (length(missing)) {
        stop("Cannot record ", stage, " lineage for channel '", channel_name,
             "': missing ", paste(missing, collapse = ", "), ".",
             call. = FALSE)
    }
    task_id <- as.character(rows$task_id)
    artifact_id <- as.character(rows[[id_column]])
    if (anyNA(task_id) || any(!nzchar(task_id)) ||
        anyNA(artifact_id) || any(!nzchar(artifact_id))) {
        stop("Activation lineage requires non-missing task and artifact IDs.",
             call. = FALSE)
    }

    source_row_ref <- if (identical(artifact_type, "source_row")) {
        artifact_id
    } else {
        .lineage_source_key(rows, "ELTID")
    }
    if (identical(artifact_type, "snippet") &&
        "hit_ref" %in% names(rows)) {
        missing_ref <- is.na(source_row_ref) | !nzchar(source_row_ref)
        source_row_ref[missing_ref] <- as.character(rows$hit_ref[missing_ref])
    }
    if (anyNA(source_row_ref) || any(!nzchar(source_row_ref))) {
        stop("Activation lineage requires every artifact to resolve to a source ",
             "row reference.", call. = FALSE)
    }
    position <- rep(NA_integer_, nrow(rows))
    if (identical(artifact_type, "snippet")) {
        position <- if ("model_candidate_rank" %in% names(rows)) {
            as.integer(rows$model_candidate_rank)
        } else {
            as.integer(stats::ave(
                seq_along(task_id), task_id,
                FUN = function(index) seq_along(index)))
        }
    }

    dplyr::distinct(tibble::tibble(
        task_id = task_id,
        variable = variable_name,
        channel = channel_name,
        source = source_name,
        stage = stage,
        artifact_type = artifact_type,
        artifact_id = artifact_id,
        source_row_ref = source_row_ref,
        artifact_position = position,
        source_PATID = .lineage_source_key(rows, "PATID"),
        source_EVTID = .lineage_source_key(rows, "EVTID"),
        source_ELTID = .lineage_source_key(rows, "ELTID")))
}

.build_channel_lineage <- function(variable, channel_name, result) {
    channel <- .channel_def(variable, channel_name)
    artifact_type <- if (identical(channel$type, "text")) {
        "snippet"
    } else {
        "source_row"
    }
    make_rows <- function(rows, stage) {
        .lineage_artifact_rows(
            rows, variable$name, channel_name, channel$source,
            stage, artifact_type)
    }

    lineage_inputs <- result$lineage_inputs
    if (is.null(lineage_inputs)) lineage_inputs <- list()
    if (!is.list(lineage_inputs) ||
        (length(lineage_inputs) > 0L && is.null(names(lineage_inputs)))) {
        stop("Channel lineage inputs must be a named list.", call. = FALSE)
    }
    unknown_stages <- setdiff(names(lineage_inputs), c("pre_selector", "window"))
    if (length(unknown_stages)) {
        stop("Unsupported upstream lineage stage(s): ",
             paste(unknown_stages, collapse = ", "), ".", call. = FALSE)
    }
    upstream_type <- if (identical(channel$type, "text")) {
        "document"
    } else {
        "source_row"
    }
    rows <- lapply(names(lineage_inputs), function(stage) {
        .lineage_artifact_rows(
            lineage_inputs[[stage]], variable$name, channel_name,
            channel$source, stage, upstream_type)
    })
    rows[[length(rows) + 1L]] <- make_rows(result$candidates, "selected")
    if (.channel_needs_chat(channel)) {
        model_input <- make_rows(result$model_candidates, "model_input")
        cited <- make_rows(result$evidence, "cited")
        if (nrow(cited)) {
            cited_key <- paste(cited$task_id, cited$artifact_id, sep = "\r")
            model_key <- paste(
                model_input$task_id, model_input$artifact_id, sep = "\r")
            position <- match(cited_key, model_key)
            if (anyNA(position)) {
                stop("Cited lineage artifact was not supplied to the model.",
                     call. = FALSE)
            }
            cited$artifact_position <- model_input$artifact_position[position]
        }
        rows[[length(rows) + 1L]] <- model_input
        rows[[length(rows) + 1L]] <- cited
    } else {
        rows[[length(rows) + 1L]] <- make_rows(result$evidence, "used")
    }
    lineage <- dplyr::bind_rows(rows)
    if (!nrow(lineage)) return(.empty_activation_lineage())

    # `stage` is the furthest stage reached, not an event log. One artifact thus
    # occupies one row even when it was selected, passed to the model, and cited.
    lineage %>%
        dplyr::mutate(
            .stage_rank = match(.data$stage, .lineage_stage_order)) %>%
        dplyr::arrange(
            .data$task_id, .data$artifact_type, .data$artifact_id,
            dplyr::desc(.data$.stage_rank)) %>%
        dplyr::distinct(
            .data$task_id, .data$artifact_type, .data$artifact_id,
            .keep_all = TRUE) %>%
        dplyr::arrange(
            .data$task_id, .data$artifact_position, .data$artifact_id) %>%
        dplyr::select(-".stage_rank")
}

.lineage_stage_rows <- function(result, stages) {
    lineage <- result$lineage
    required <- c("task_id", "stage", "artifact_id")
    if (!is.data.frame(lineage) || !all(required %in% names(lineage))) {
        stop("Channel result is missing its activation lineage.", call. = FALSE)
    }
    lineage[lineage$stage %in% stages, , drop = FALSE]
}

.lineage_stage_counts <- function(result, task_ids, stages,
                                  artifact_type = NULL) {
    rows <- .lineage_stage_rows(result, stages)
    if (!is.null(artifact_type)) {
        rows <- rows[rows$artifact_type %in% artifact_type, , drop = FALSE]
    }
    tabulate(
        match(as.character(rows$task_id), as.character(task_ids)),
        nbins = length(task_ids))
}

.lineage_reached_counts <- function(result, task_ids, stage, artifact_type) {
    target_rank <- match(stage, .lineage_stage_order)
    if (is.na(target_rank)) {
        stop("Unknown lineage stage: ", stage, ".", call. = FALSE)
    }
    reached <- .lineage_stage_order[
        seq.int(target_rank, length(.lineage_stage_order))]
    .lineage_stage_counts(
        result, task_ids, reached, artifact_type = artifact_type)
}

.build_audit_lineage <- function(channel_results) {
    rows <- lapply(channel_results, `[[`, "lineage")
    result <- dplyr::bind_rows(rows)
    if (nrow(result)) result else .empty_activation_lineage()
}
