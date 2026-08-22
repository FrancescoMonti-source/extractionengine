# =============================================================================
# channel-combine.R — per-channel reduction to the {status, hit} contract
# -----------------------------------------------------------------------------
# Reduces ONE selected channel's coverage/value views to per-task status and hit
# vectors consumed by the value assemblers in run_variable() -- the hit-set
# expression evaluator (.hit_set_expr_variable) and the single-channel membership
# assembler (.single_membership_variable). Evidence is published separately from
# the executor result. The reducer maps the engine's processing_state vocabulary
# (text OR structured) into a normalized {complete / unavailable / invalid / error}
# status plus a three-valued hit (TRUE / FALSE / NA).
#
# "source" is reserved for the warehouse/raw data source (e.g. pmsi_diag, documents,
# biology); a channel reads FROM a source but is not the source. The only raw-source
# field that survives here is the durable evidence row key (source_row_id), genuine
# warehouse metadata.
#
# (The original OR collapse combine_any_channel_hit() -- the open-world
# incomplete_value policy -- was removed once cross-channel combine became hit-set
# algebra: that value is always 0/1 with the uncertainty on channel_coverage, never
# an incomplete_value. The pre-spine diabetes orchestration helpers were likewise
# subsumed by run_variable(); OR resilience is exercised at the spine, see
# test-slice-diabetes-spec.R / test-slice-dialysis-spec.R.)
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
    states <- rep("no_eligible_source", length(task_ids))
    found <- !is.na(index)
    states[found] <- as.character(result$coverage$processing_state[index[found]])
    states
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

# Reduce one channel's coverage/value views to one ordered {task_id, status, hit}
# table. Evidence is published directly from the executor result and does not
# belong in this decision reducer.
.reduce_channel_result <- function(
    res,
    task_ids,
    no_candidate_status = c("complete", "unavailable")) {
    no_candidate_status <- match.arg(no_candidate_status)
    states <- .states_for_tasks(res, task_ids)
    accepted <- .accepted_values_for_tasks(res, task_ids)

    status <- rep("unavailable", length(task_ids))
    status[states %in% c("measured", "valid")] <- "complete"
    status[states %in% "no_candidate"] <- no_candidate_status
    status[states %in% "invalid"] <- "invalid"
    status[states %in% c("model_error", "processing_error")] <- "error"

    hit <- rep(NA, length(task_ids))
    complete <- states %in% c("measured", "valid")
    hit[complete] <- !is.na(accepted[complete]) & accepted[complete] == "present"
    if (identical(no_candidate_status, "complete")) {
        hit[states %in% "no_candidate"] <- FALSE
    }

    tibble::tibble(
        task_id = as.character(task_ids),
        status = status,
        hit = hit)
}
