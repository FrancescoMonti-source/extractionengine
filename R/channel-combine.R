# =============================================================================
# channel-combine.R — task-keyed executor views and membership reduction
# -----------------------------------------------------------------------------
# Reduces ONE selected activation to the three-valued observed hit
# (TRUE / FALSE / NA) that the deterministic assemblers consume; no executor
# fact is translated into a public completeness label. The two inputs are the
# activation lineage and, for a model activation, the attempts relation: no
# executor publishes a per-task state frame any more. The LLM membership path
# keeps its own public status vocabulary until that contract is rewritten.
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
# assemblers have always assumed at most one value row per task; make that
# invariant executable instead of silently taking the first match.
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


# Deterministic membership is two facts about the activation and nothing else:
# whether the task had a universe to search at all, and whether any artifact
# reached `selected`. A task the engine never looked at stays NA; a task it
# looked at and found nothing in is FALSE.
.deterministic_hits_for_tasks <- function(res, task_ids) {
    eligible <- .activation_eligibility(res, task_ids)
    selected <- .lineage_stage_counts(res, task_ids, .lineage_selected_stages)
    hit <- rep(NA, length(task_ids))
    hit[eligible] <- selected[eligible] > 0L
    tibble::tibble(
        task_id = as.character(task_ids),
        hit = hit)
}

