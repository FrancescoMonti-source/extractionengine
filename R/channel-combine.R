# =============================================================================
# channel-combine.R — task-keyed executor views and membership reduction
# -----------------------------------------------------------------------------
# Reads ONE selected channel's coverage/value views as total task-keyed relations.
# Deterministic assemblers consume only a three-valued observed hit
# (TRUE / FALSE / NA); they do not translate executor facts into a public
# completeness label. The legacy status reducer remains isolated to the LLM
# membership path, whose contract is not rewritten in Phase 3.
#
# "source" is reserved for the warehouse/raw data source (e.g. pmsi_diag, documents,
# biology); a channel reads FROM a source but is not the source. The only raw-source
# field that survives here is the durable evidence row key (source_row_id), genuine
# warehouse metadata.
#
# (The original OR collapse combine_any_channel_hit() -- the open-world
# incomplete_value policy -- was removed once cross-channel combine became hit-set
# algebra. The pre-spine diabetes orchestration helpers were likewise subsumed by
# run_variable().)
# =============================================================================

# Return the position of each declared task in a task-keyed executor view. The
# assemblers have always assumed at most one coverage/value row per task; make
# that invariant executable instead of silently taking the first match.
.task_row_index <- function(frame, task_ids, required, frame_name,
                            allow_columnless_empty = FALSE) {
    if (!is.data.frame(frame)) {
        stop(frame_name, " must be a data frame.", call. = FALSE)
    }
    if (!nrow(frame) && allow_columnless_empty) {
        return(rep.int(NA_integer_, length(task_ids)))
    }
    missing <- setdiff(c("task_id", required), names(frame))
    if (length(missing)) {
        stop(frame_name, " is missing required column(s): ",
             paste(missing, collapse = ", "), ".", call. = FALSE)
    }
    frame_ids <- as.character(frame$task_id)
    if (anyDuplicated(frame_ids)) {
        stop(frame_name, " must have at most one row per task_id.",
             call. = FALSE)
    }
    match(as.character(task_ids), frame_ids)
}

.states_for_tasks <- function(result, task_ids) {
    index <- .task_row_index(
        result$coverage, task_ids, "processing_state", "Channel coverage")
    coverage_ids <- as.character(result$coverage$task_id)
    task_ids <- as.character(task_ids)
    missing_ids <- task_ids[is.na(index)]
    unexpected_ids <- setdiff(coverage_ids, task_ids)
    if (length(missing_ids) || length(unexpected_ids)) {
        details <- c(
            if (length(missing_ids)) {
                paste0("missing: ", paste(missing_ids, collapse = ", "))
            },
            if (length(unexpected_ids)) {
                paste0("unexpected: ", paste(unexpected_ids, collapse = ", "))
            })
        stop("Channel coverage must contain exactly one row for every task_id (",
             paste(details, collapse = "; "), ").", call. = FALSE)
    }
    as.character(result$coverage$processing_state[index])
}

.check_processing_states <- function(states, allowed, context) {
    unexpected <- unique(states[is.na(states) | !states %in% allowed])
    if (!length(unexpected)) return(invisible(states))
    labels <- ifelse(is.na(unexpected), "<NA>", unexpected)
    stop(context, " returned unsupported processing_state value(s): ",
         paste(labels, collapse = ", "), ".", call. = FALSE)
}

.accepted_values_for_tasks <- function(result, task_ids) {
    index <- .task_row_index(
        result$values, task_ids, "accepted_value", "Channel values",
        allow_columnless_empty = TRUE)
    accepted <- rep(NA_character_, length(task_ids))
    found <- !is.na(index)
    accepted[found] <- as.character(result$values$accepted_value[index[found]])
    accepted
}

# Reduce deterministic executor facts directly to observed membership. Missing
# source rows remain NA in the audit vector; no selected candidate is FALSE.
.deterministic_hits_for_tasks <- function(res, task_ids, channel_name) {
    states <- .states_for_tasks(res, task_ids)
    allowed <- c(
        "measured", "no_candidate", "no_eligible_source",
        "no_eligible_document")
    .check_processing_states(
        states, allowed, paste0("Deterministic channel '", channel_name, "'"))
    accepted <- .accepted_values_for_tasks(res, task_ids)

    hit <- rep(NA, length(task_ids))
    measured <- states == "measured"
    hit[measured] <- !is.na(accepted[measured]) &
        accepted[measured] == "present"
    hit[states == "no_candidate"] <- FALSE

    tibble::tibble(
        task_id = as.character(task_ids),
        hit = hit)
}

# The LLM membership path still consumes the historical status vocabulary. Keep
# that translation explicit and closed until the LLM contract is rewritten.
.reduce_llm_channel_result <- function(res, task_ids) {
    states <- .states_for_tasks(res, task_ids)
    allowed <- c(
        "valid", "no_candidate", "no_eligible_document", "not_called",
        "invalid", "model_error", "processing_error")
    .check_processing_states(states, allowed, "LLM channel")
    accepted <- .accepted_values_for_tasks(res, task_ids)

    status <- rep(NA_character_, length(task_ids))
    status[states == "valid"] <- "complete"
    status[states %in%
        c("no_candidate", "no_eligible_document", "not_called")] <- "unavailable"
    status[states == "invalid"] <- "invalid"
    status[states %in% c("model_error", "processing_error")] <- "error"

    hit <- rep(NA, length(task_ids))
    hit[states == "valid"] <- !is.na(accepted[states == "valid"]) &
        accepted[states == "valid"] == "present"

    tibble::tibble(
        task_id = as.character(task_ids),
        status = status,
        hit = hit)
}
