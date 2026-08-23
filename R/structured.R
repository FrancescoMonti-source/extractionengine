# =============================================================================
# structured.R — deterministic (non-LLM) extraction path for STRUCTURED sources
# -----------------------------------------------------------------------------
# Evidence = selected source rows, measurement = a deterministic rule, NO corpus
# and NO model. NEUTRAL, concept-agnostic executors only: measure_code_presence
# (code/act membership) and measure_analyte_values (valued rows of an analyte in
# a window -- the output expression is evaluated later during assembly); the
# run_variable() dispatch binds each to its source. These executors no longer
# summarise tasks into a per-task state: what an activation could look at, what
# it selected, and what a filter demoted are stages of the activation lineage,
# and the census over ALL tasks is taken there. Provenance points at the exact
# source rows.
# =============================================================================

# --- contract / provenance helpers ------------------------------------------

.require_columns <- function(x, required, label) {
    missing <- setdiff(required, names(x))
    if (length(missing)) {
        stop(label, " requires: ", paste(required, collapse = ", "),
             "; missing: ", paste(missing, collapse = ", "), call. = FALSE)
    }
}

.validate_structured_inputs <- function(tasks, source_rows, source_required, source_label,
                                        require_anchor = TRUE) {
    task_cols <- if (require_anchor) c("task_id", "PATID", "anchor_date")
                 else c("task_id", "PATID")
    .require_columns(tasks, task_cols, "tasks")
    .require_columns(source_rows, source_required, source_label)

    task_ids <- as.character(tasks$task_id)
    source_ids <- as.character(source_rows$source_row_id)
    if (anyNA(task_ids) || any(!nzchar(task_ids)) || anyDuplicated(task_ids)) {
        stop("tasks$task_id must be non-missing and unique", call. = FALSE)
    }
    if (anyNA(tasks$PATID) || any(!nzchar(as.character(tasks$PATID)))) {
        stop("tasks$PATID must be non-missing", call. = FALSE)
    }
    if (require_anchor && anyNA(tasks$anchor_date)) {
        stop("tasks$anchor_date must be non-missing", call. = FALSE)
    }
    if (anyNA(source_ids) || any(!nzchar(source_ids)) || anyDuplicated(source_ids)) {
        stop(source_label, "$source_row_id must be non-missing and unique",
             call. = FALSE)
    }
    invisible(TRUE)
}

.clinical_date <- function(x) {
    if (inherits(x, "POSIXt")) {
        return(as.Date(x, tz = "Europe/Paris"))
    }
    if (inherits(x, "Date")) return(x)
    stop("Expected a Date or POSIXt value.",
         call. = FALSE)
}

# --- scope helpers (point / interval) ----------------------------------------

.within_point <- function(t, lo, hi) !is.na(t) & t >= lo & t <= hi

# Find data-column references without evaluating author code. A bare name always
# means a prepared-source column. The one exception is a name whose nearest
# ordinary lexical binding is a function: `mean` handed to `vapply()`, an
# operator handed to `Reduce()`, an authored helper -- those are author code,
# not data. Active and lazy bindings are not forced during validation. Every
# other object the quosure environment happens to carry must be read explicitly
# through `.env$`, or a misspelled column that collides with a session binding
# publishes that binding's value with genuine evidence rows attached to it.
# Explicit .data accesses always name prepared columns. The walk is static, so a
# misspelled column fails even when the selector produces zero target rows.
# It returns both halves of what the expression reads: `columns` from the
# prepared source, and `external`, the `.env$` names it reaches outside it.
.data_mask_references <- function(expression) {
    env <- rlang::quo_get_env(expression)
    required <- character()
    external <- character()

    is_function_binding <- function(name) {
        binding_env <- env
        while (!identical(binding_env, emptyenv())) {
            if (rlang::env_has(binding_env, name, inherit = FALSE)) {
                if (rlang::env_binding_are_active(binding_env, name) ||
                    rlang::env_binding_are_lazy(binding_env, name)) {
                    return(FALSE)
                }
                return(is.function(rlang::env_get(
                    binding_env, name, inherit = FALSE)))
            }
            binding_env <- rlang::env_parent(binding_env)
        }
        FALSE
    }

    resolve_pronoun_key <- function(node, pronoun) {
        key <- if (is.character(node) && length(node) == 1L) {
            node
        } else if (rlang::is_symbol(node)) {
            name <- rlang::as_string(node)
            if (!rlang::env_has(env, name, inherit = TRUE)) {
                stop(pronoun, "[[", name,
                     "]] requires that '", name,
                     "' be defined in the expression environment.",
                     call. = FALSE)
            }
            rlang::env_get(env, name, inherit = TRUE)
        } else {
            stop(pronoun,
                 "[[...]] accepts only a literal column name or a symbol ",
                 "bound to one; author code is not executed during validation.",
                 call. = FALSE)
        }
        if (!is.character(key) || length(key) != 1L ||
            is.na(key) || !nzchar(key)) {
            stop(pronoun,
                 "[[...]] must resolve to one non-empty name.",
                 call. = FALSE)
        }
        key
    }

    visit <- function(node, locals = character()) {
        if (rlang::is_symbol(node)) {
            name <- rlang::as_string(node)
            if (name %in% c(".data", ".env", locals) ||
                is_function_binding(name)) {
                return(locals)
            }
            required <<- c(required, name)
            return(locals)
        }
        if (!rlang::is_call(node)) return(locals)

        if (rlang::is_call(node, "{")) {
            for (argument in as.list(node)[-1L]) {
                locals <- visit(argument, locals)
            }
            return(locals)
        }
        if ((rlang::is_call(node, "<-") || rlang::is_call(node, "=")) &&
            length(node) >= 3L && rlang::is_symbol(node[[2L]])) {
            locals <- visit(node[[3L]], locals)
            return(unique(c(locals, rlang::as_string(node[[2L]]))))
        }
        # Only assignments reached sequentially in a `{}` block are known to
        # define a name for later expressions. An exhaustive if/else may also
        # define names, but only those defined by both branches.
        if (rlang::is_call(node, "if")) {
            condition_locals <- visit(node[[2L]], locals)
            then_locals <- visit(node[[3L]], condition_locals)
            if (length(node) < 4L) return(condition_locals)
            else_locals <- visit(node[[4L]], condition_locals)
            return(unique(c(
                condition_locals,
                intersect(then_locals, else_locals)
            )))
        }
        if (rlang::is_call(node, "for") && length(node) >= 4L &&
            rlang::is_symbol(node[[2L]])) {
            visit(node[[3L]], locals)
            loop_locals <- unique(c(locals, rlang::as_string(node[[2L]])))
            visit(node[[4L]], loop_locals)
            return(locals)
        }
        if (rlang::is_call(node, "while") || rlang::is_call(node, "repeat")) {
            for (argument in as.list(node)[-1L]) visit(argument, locals)
            return(locals)
        }
        if (rlang::is_call(node, "function") && length(node) >= 3L) {
            formals <- names(as.list(node[[2L]]))
            visit(node[[3L]], unique(c(locals, formals)))
            return(locals)
        }
        if (rlang::is_call(node, "~")) {
            formula_locals <- unique(c(
                locals, ".", ".x", ".y", "..1", "..2"
            ))
            for (argument in as.list(node)[-1L]) {
                visit(argument, formula_locals)
            }
            return(locals)
        }

        operator <- node[[1L]]
        if (rlang::is_symbol(operator) &&
            rlang::as_string(operator) %in% c("$", "[[")) {
            object <- node[[2L]]
            if (rlang::is_symbol(object, ".data")) {
                key <- if (rlang::is_call(node, "$")) {
                    rlang::as_string(node[[3L]])
                } else {
                    resolve_pronoun_key(node[[3L]], ".data")
                }
                required <<- c(required, key)
                return(locals)
            }
            if (rlang::is_symbol(object, ".env")) {
                key <- if (rlang::is_call(node, "$")) {
                    rlang::as_string(node[[3L]])
                } else {
                    resolve_pronoun_key(node[[3L]], ".env")
                }
                if (!rlang::env_has(env, key, inherit = TRUE)) {
                    stop(".env$", key, " is not defined in the expression environment.",
                         call. = FALSE)
                }
                external <<- c(external, key)
                return(locals)
            }
            # In ordinary `$`, the field name is not evaluated. An ordinary
            # `[[` index is, so visit it after the object.
            visit(object, locals)
            if (rlang::is_call(node, "[[")) {
                visit(node[[3L]], locals)
            }
            return(locals)
        }

        # The call head names a function/operator, not a data column.
        for (argument in as.list(node)[-1L]) {
            visit(argument, locals)
        }
        locals
    }

    visit(rlang::quo_get_expr(expression))
    list(columns = unique(required), external = unique(external))
}

.validate_data_mask_expression <- function(expression, columns, field, what) {
    if (!rlang::is_quosure(expression)) {
        stop(what, " for channel '", field,
             "' is not a captured data-masked expression.", call. = FALSE)
    }
    references <- tryCatch(
        .data_mask_references(expression),
        error = function(cnd) {
            stop(what, " for channel '", field,
                 "' could not resolve its data-mask references: ",
                 conditionMessage(cnd), call. = FALSE)
        })
    missing <- setdiff(references$columns, columns)
    if (length(missing)) {
        stop(what, " for channel '", field,
             "' references missing prepared-source column(s): ",
             paste(missing, collapse = ", "), ". Available columns: ",
             paste(columns, collapse = ", "),
             ". A bare name is a prepared-source column; read an external ",
             "value with .env$name.", call. = FALSE)
    }
    invisible(TRUE)
}

# --- frozen external parameters ----------------------------------------------
# `NUMRES < .env$soglia` answers differently when soglia is 12 and when it is 13,
# and nothing recorded which one ran. The values are therefore photographed once,
# before any activation executes, and the same photograph feeds the calculation
# and the manifest -- a manifest agreeing with a value the executor re-read later
# would be an audit lie no review of the values can catch.
#
# Only a simple value is photographed. A list, an object, or a function stays
# live: `.env$weight_options$remove_missing` is the idiom the data-mask rule
# already requires for an option list, so rejecting it would break authoring that
# this package made mandatory, and serializing it would put the authoring session
# in the audit trail. The manifest records such a name as read and not captured,
# because a run that silently omitted the dependency would claim a
# reproducibility it does not have.
.is_simple_parameter <- function(value) {
    if (is.null(value) || !is.atomic(value)) return(FALSE)
    carried <- setdiff(names(attributes(value)), c("names", "class", "tzone"))
    if (length(carried)) return(FALSE)
    inherits(value, c("Date", "POSIXct")) ||
        identical(class(value), typeof(value)) ||
        identical(class(value), "numeric")
}

# Rewrite every data-masked quosure in a resolved definition. The walk is
# generic, like the manifest snapshot: a future authoring argument that captures
# an expression is frozen without an edit here.
.map_spec_quosures <- function(x, transform) {
    if (rlang::is_quosure(x)) return(transform(x))
    if (!is.list(x)) return(x)
    mapped <- lapply(unclass(x), .map_spec_quosures, transform = transform)
    attributes(mapped) <- attributes(x)
    mapped
}

.freeze_env_parameters <- function(variable) {
    captured <- list()
    not_captured <- character()
    freeze <- function(quosure) {
        env <- rlang::quo_get_env(quosure)
        keys <- .data_mask_references(quosure)$external
        frozen <- list()
        for (key in keys) {
            value <- rlang::env_get(env, key, inherit = TRUE)
            if (!.is_simple_parameter(value)) {
                not_captured <<- unique(c(not_captured, key))
                next
            }
            # One variable is one definition: a name that means two different
            # values inside it cannot be recorded once, and choosing either
            # would misdescribe the other expression.
            if (key %in% names(captured) &&
                !identical(captured[[key]], value)) {
                stop("Expressions of variable '", variable$name,
                     "' read .env$", key,
                     " with two different values; rename one of them so the ",
                     "manifest can record what ran.", call. = FALSE)
            }
            frozen[[key]] <- value
            captured[[key]] <<- value
        }
        if (!length(frozen)) return(quosure)
        rlang::quo_set_env(
            quosure, rlang::new_environment(data = frozen, parent = env))
    }
    list(
        variable = .map_spec_quosures(variable, freeze),
        parameters = list(captured = captured, not_captured = not_captured))
}

# Data-masked activation expressions see complete prepared-source columns and the
# quosure's lexical environment. Evaluation errors are reported at the channel
# boundary with the available columns so a missing prepared-view column stays a
# source-contract error rather than an opaque tidy-eval failure.
.eval_activation_expression <- function(rows, expression, field, what,
                                        mask_columns) {
    mask <- rows[intersect(mask_columns, names(rows))]
    tryCatch(
        rlang::eval_tidy(expression, data = mask),
        error = function(cnd) {
            stop(what, " for channel '", field,
                 "' could not be evaluated against prepared-source columns ",
                 paste(names(mask), collapse = ", "), ": ",
                 conditionMessage(cnd), call. = FALSE)
        })
}

# A row predicate returns one logical per row. An NA result is not a hit.
.eval_row_predicate <- function(rows, filter_rows, field, mask_columns) {
    res <- .eval_activation_expression(
        rows, filter_rows, field, "filter_rows", mask_columns)
    if (!is.logical(res) || length(res) != nrow(rows)) {
        stop("filter_rows for channel '", field, "' must return one logical ",
             "per row (got ", class(res)[1L], " of length ", length(res), " for ",
             nrow(rows), " rows); a row predicate breaking its contract is a bug.",
             call. = FALSE)
    }
    res & !is.na(res)
}

# Apply a row predicate independently to each task's current target rows. Demoted
# rows stay in observations and NA predicate results are false.
.apply_row_predicate <- function(observations, filter_rows, field,
                                 mask_columns) {
    observations$row_demoted <- FALSE
    if (is.null(filter_rows)) return(observations)

    .validate_data_mask_expression(
        filter_rows, mask_columns, field, "filter_rows")
    target_rows <- which(observations$is_target)
    if (!length(target_rows)) return(observations)
    by_task <- split(target_rows, observations$task_id[target_rows])
    for (idx in by_task) {
        keep <- .eval_row_predicate(
            observations[idx, , drop = FALSE], filter_rows, field,
            mask_columns)
        observations$row_demoted[idx] <- !keep
        observations$is_target[idx] <- keep
    }
    observations
}

# Aggregate predicate: evaluate the data-masked expression on current target rows,
# separately for every task + declared level. For lab channels these are the rows
# that survived filter_rows. Failing groups are demoted in-place so observations
# retain the complete audit trail.
.apply_group_predicate <- function(observations, group_by,
                                   filter_groups, field, mask_columns) {
    observations$group_demoted <- FALSE
    if (is.null(filter_groups)) return(observations)
    if (is.null(group_by) || !group_by %in% mask_columns) {
        stop("filter_groups for channel '", field, "' groups by '",
             group_by, "', which the prepared source does not carry.",
             call. = FALSE)
    }

    .validate_data_mask_expression(
        filter_groups, mask_columns, field, "filter_groups")
    target_rows <- which(observations$is_target)
    if (!length(target_rows)) return(observations)
    group_key <- paste(observations$task_id[target_rows],
                       observations[[group_by]][target_rows], sep = "\r")
    groups <- split(target_rows, group_key)
    keep <- vapply(groups, function(idx) {
        rows <- observations[idx, , drop = FALSE]
        res <- .eval_activation_expression(
            rows, filter_groups, field, "filter_groups", mask_columns)
        if (!is.logical(res) || length(res) != 1L || is.na(res)) {
            stop("filter_groups for channel '", field,
                 "' must return exactly one TRUE/FALSE per task + ",
                 group_by, " group; a group predicate breaking its ",
                 "contract is a bug.", call. = FALSE)
        }
        res
    }, logical(1))
    demoted <- unlist(groups[!keep], use.names = FALSE)
    if (length(demoted)) {
        observations$group_demoted[demoted] <- TRUE
        observations$is_target[demoted] <- FALSE
    }
    observations
}

.overlaps_interval <- function(start, end, lo, hi,
                               missing_datsort = c("use_start", "exclude")) {
    missing_datsort <- match.arg(missing_datsort)
    end_eff <- if (identical(missing_datsort, "use_start")) {
        dplyr::coalesce(end, start)
    } else {
        end
    }
    !is.na(start) & start <= hi & end_eff >= lo
}

# Code matching for a coded channel. The code is NORMALIZED (dots/spaces stripped,
# upper-cased) before matching, so "E11.9" and "E119" are the same code.
#   - exact: normalized code is in the declared set
#   - regex: normalized code matches ANY declared pattern (e.g. "^E1[0-4]")
# No usability/shape check -- HDW codes are standardized (CIM-10 in pmsi$diag, CCAM
# in pmsi$actes), so there is no "malformed code" to route to review.
.code_matches <- function(codes, patterns, match = c("regex", "exact")) {
    match <- match.arg(match)
    ncodes <- toupper(gsub("[^A-Za-z0-9]", "", as.character(codes)))
    ok <- !is.na(ncodes) & nzchar(ncodes)
    if (identical(match, "exact")) {
        target <- toupper(gsub("[^A-Za-z0-9]", "", as.character(patterns)))
        target <- target[!is.na(target) & nzchar(target)]
        ok & ncodes %in% target
    } else {
        pats <- as.character(patterns)
        pats <- pats[!is.na(pats) & nzchar(pats)]
        hit <- rep(FALSE, length(ncodes))
        for (p in pats) hit <- hit | grepl(p, ncodes, perl = TRUE)
        ok & hit
    }
}

# A row that matched the selector and was then demoted by an activation filter
# stops at `selector`; a row that never matched stops at `window`, or at
# `pre_selector` when the activation declares no window. Keeping those two apart
# is what retires the observation frame from the audit path: the pre-filter
# boundary becomes a lineage count, and what the filters removed stays visible
# per artifact instead of only as the difference between two totals.
.structured_lineage_inputs <- function(pre_selector, scoped, observations,
                                       windowed) {
    inputs <- list(
        pre_selector = .lineage_input_rows(pre_selector, "source_row"))
    if (windowed) {
        inputs$window <- .lineage_input_rows(scoped, "source_row")
    }
    matched_selector <- observations$is_target | observations$row_demoted |
        observations$group_demoted
    inputs$selector <- .lineage_input_rows(
        observations[matched_selector, , drop = FALSE], "source_row")
    inputs
}

# --- generic code presence: a code family over a coded source ------------------
# Neutral structured executor behind a run_variable() code channel over a coded
# source (for example CIM-10 / pmsi$diag or CCAM / pmsi$actes). It selects the
# rows whose code is in the declared family and in scope, and returns them with
# their evidence and their lineage; whether a task is present, absent, or was
# never given a universe to search is read from that lineage downstream, not
# summarised here. The caller resolves the PHYSICAL columns from the source's
# roles:
# `code_col` holds the code; `start_col`/`end_col` the time interval (a point-dated
# source passes one date for both). `match` is exact (a code set) or regex. `field` /
# `source` name the output rows; `codes` is the declared family (no concept baked in).
#
# source_table: a coded source frame
#   source_row_id, PATID, EVTID, ELTID, <code_col>, <start_col>, <end_col>.
# tasks: task_id, PATID, anchor_date (anchor only when windowed).
measure_code_presence <- function(source_table, tasks, codes,
                                  match = c("regex", "exact"),
                                  filter_rows = NULL,
                                  grain_keys = "PATID",
                                  from_days = NULL, to_days = NULL,
                                  group_by = NULL, filter_groups = NULL,
                                  code_col = "diag", start_col = "DATENT",
                                  end_col = "DATSORT",
                                  missing_end = c("use_start", "exclude"),
                                  field = "code_presence", source = "diagnosis") {
    match <- match.arg(match)
    missing_end <- match.arg(missing_end)
    windowed <- !is.null(from_days) && !is.null(to_days)   # NULL window -> whole history
    # Grain is declared by the output contract (output$group_by) and passed as grain_keys by
    # the caller (run_variable): "PATID" alone scopes by subject (patient grain);
    # c("PATID","EVTID") scopes each task to its OWN stay (stay grain) -- closing the
    # DESIGN §7 executor gap ("EVTID is invariant across HDW rows"). The task
    # join uses grain_keys, so every artifact is associated per grain unit.
    .validate_structured_inputs(
        tasks, source_table,
        unique(c("source_row_id", "PATID", "EVTID", "ELTID",
                 code_col, start_col, end_col)),
        "coded rows", require_anchor = windowed)

    source_columns <- names(source_table)
    rows <- tibble::as_tibble(source_table) %>%
        mutate(
            source_row_id = as.character(source_row_id),
            .ee_t_start = .clinical_date(.data[[start_col]]),
            .ee_t_end = .clinical_date(.data[[end_col]]))
    tkeys <- tasks %>%
        transmute(task_id = as.character(task_id), PATID = as.character(PATID))
    for (k in setdiff(grain_keys, "PATID")) tkeys[[k]] <- as.character(tasks[[k]])
    if (windowed) tkeys$anchor_date <- .clinical_date(tasks$anchor_date)

    pre_selector <- rows %>%
        inner_join(tkeys, by = grain_keys, relationship = "many-to-many")

    scoped <- pre_selector
    if (windowed) {
        scoped <- scoped %>% filter(.overlaps_interval(
            .data$.ee_t_start, .data$.ee_t_end,
            anchor_date + from_days, anchor_date + to_days,
            missing_datsort = missing_end))
    }
    observations <- scoped %>%
        mutate(
            field = field,
            source = source,
            in_scope = TRUE,
            is_target = .code_matches(.data[[code_col]], codes, match))

    observations <- .apply_row_predicate(
        observations, filter_rows, field, source_columns)
    observations <- .apply_group_predicate(
        observations, group_by, filter_groups, field, source_columns)

    observations <- observations %>%
        mutate(
            selected_evidence = is_target,
            scope_reason = if (windowed) "in scope for the task window"
                           else "whole history (no window)",
            observation_reason = case_when(
                .data$is_target ~ "code matches the declared family",
                .data$group_demoted ~ "group aggregate predicate not satisfied",
                .data$row_demoted ~ "row predicate not satisfied",
                TRUE ~ "code outside the declared family"))


    candidate_columns <- unique(c("task_id", source_columns))
    candidates <- observations %>%
        filter(is_target) %>%
        arrange(task_id, .data$.ee_t_start, source_row_id) %>%
        select(all_of(candidate_columns))

    evidence_columns <- unique(c(
        "task_id", "field", "source", "source_row_id", "evidence_ref",
        "evidence_summary", setdiff(source_columns, "source_row_id")))
    evidence <- observations %>%
        filter(selected_evidence) %>%
        mutate(
            evidence_ref = source_row_id,
            evidence_summary = sprintf(
                "%s (%s)", .data[[code_col]], .data$.ee_t_start)) %>%
        select(all_of(evidence_columns))

    list(
        candidates = candidates,
        evidence = evidence,
        lineage_inputs = .structured_lineage_inputs(
            pre_selector, scoped, observations, windowed))
}

# --- generic document presence: metadata-selected docs_index rows ---------------
# Neutral executor behind the run_variable() doc branch: a document's EXISTENCE is
# the hit, selected on docs_index METADATA (exact any-of filters per column) -- no
# content, no Lucene, no LLM. Same present/absent membership contract as the code
# executor, so a doc hit means the same thing inside a hit-set expression. Matching
# candidates retain the full metadata row for explicit from_channel() projection.
#
# docs_index: ELTID (unique), PATID, EVTID, <date_col>, plus the filter columns.
# tasks: task_id, PATID (+ grain keys); anchor_date only when windowed.
measure_doc_presence <- function(docs_index, tasks, filters,
                                 filter_rows = NULL,
                                 grain_keys = "PATID",
                                 from_days = NULL, to_days = NULL,
                                 group_by = NULL, filter_groups = NULL,
                                 date_col = "RECDATE",
                                 field = "doc_presence", source = "documents") {
    windowed <- !is.null(from_days) && !is.null(to_days)   # NULL window -> whole history
    .require_columns(docs_index,
                     unique(c("ELTID", "PATID", "EVTID", date_col, names(filters))),
                     "docs index")

    source_columns <- names(docs_index)
    rows <- tibble::as_tibble(docs_index) %>% mutate(
        source_row_id = ELTID,
        .ee_doc_date = .clinical_date(.data[[date_col]]))
    .validate_structured_inputs(
        tasks, rows,
        c("source_row_id", "PATID", "EVTID", "ELTID", ".ee_doc_date"),
        "docs index", require_anchor = windowed)

    tkeys <- tasks %>%
        transmute(task_id = as.character(task_id), PATID = as.character(PATID))
    for (k in setdiff(grain_keys, "PATID")) tkeys[[k]] <- as.character(tasks[[k]])
    if (windowed) tkeys$anchor_date <- .clinical_date(tasks$anchor_date)

    pre_selector <- rows %>%
        inner_join(tkeys, by = grain_keys, relationship = "many-to-many")

    scoped <- pre_selector
    if (windowed) {
        scoped <- scoped %>% filter(.within_point(
            .data$.ee_doc_date,
            anchor_date + from_days, anchor_date + to_days))
    }
    matches <- rep(TRUE, nrow(scoped))
    for (cl in names(filters)) {
        matches <- matches & (as.character(scoped[[cl]]) %in% filters[[cl]])
    }
    observations <- scoped %>%
        mutate(
            field = field,
            source = source,
            in_scope = TRUE,
            is_target = matches & !is.na(matches))

    observations <- .apply_row_predicate(
        observations, filter_rows, field, source_columns)
    observations <- .apply_group_predicate(
        observations, group_by, filter_groups, field, source_columns)

    observations <- observations %>%
        mutate(
            selected_evidence = is_target,
            scope_reason = if (windowed) "in scope for the task window"
                           else "whole history (no window)",
            observation_reason = case_when(
                .data$is_target ~ "document metadata matches the declared filters",
                .data$group_demoted ~ "group aggregate predicate not satisfied",
                .data$row_demoted ~ "row predicate not satisfied",
                TRUE ~ "document metadata outside the declared filters"))


    filter_txt <- paste(vapply(names(filters), function(cl) {
        sprintf("%s in {%s}", cl, paste(filters[[cl]], collapse = ","))
    }, character(1)), collapse = "; ")

    candidate_columns <- unique(c(
        "task_id", "source_row_id", source_columns))
    candidates <- observations %>%
        filter(is_target) %>%
        arrange(task_id, .data$.ee_doc_date, source_row_id) %>%
        select(all_of(candidate_columns))

    evidence_columns <- unique(c(
        "task_id", "field", "source", "source_row_id", "evidence_ref",
        "evidence_summary", source_columns))
    evidence <- observations %>%
        filter(selected_evidence) %>%
        mutate(
            evidence_ref = source_row_id,
            evidence_summary = sprintf(
                "%s (%s)", filter_txt, .data$.ee_doc_date)) %>%
        select(all_of(evidence_columns))

    list(
        candidates = candidates,
        evidence = evidence,
        lineage_inputs = .structured_lineage_inputs(
            pre_selector, scoped, observations, windowed))
}

# --- generic analyte candidates: selected prepared rows in a point-window -------
# The lab executor selects rows by the source's analyte role only. NUMRES, STRRES,
# DATEXAM, identifiers, units, qualifiers and role-less predicate columns remain
# ordinary prepared-source columns; `from_channel(value =)` evaluates its payload
# expression downstream. A row may therefore carry either, both, or neither result
# column.
#
# filter_rows is evaluated on analyte matches separately for each task after grain and
# window scoping. filter_groups then sees the surviving rows in each task + group_by
# group. Both filters demote rows in observations without stripping source payload.
measure_analyte_values <- function(source_table, tasks, analytes,
                                   filter_rows = NULL,
                                   grain_keys = "PATID",
                                   from_days = -7L, to_days = 7L,
                                   group_by = NULL, filter_groups = NULL,
                                   date_col = "DATEXAM",
                                   analyte_col = "TYPEANA",
                                   field = "analyte", source = "biology") {
    windowed <- !is.null(from_days) && !is.null(to_days)   # NULL window -> event scope
    .validate_structured_inputs(
        tasks, source_table,
        unique(c("source_row_id", "PATID", "EVTID", "ELTID",
                 date_col, analyte_col)),
        "biology rows", require_anchor = windowed)

    # Preserve the complete prepared row. Only identifier/date role columns are
    # normalized for joins and window arithmetic; result columns are never inferred
    # or collapsed into a synthetic `value` lane.
    biol <- tibble::as_tibble(source_table)
    source_columns <- names(biol)
    # The native exam identifier is optional provenance. `source_row_id` is the
    # execution coordinate for each prepared result row.
    id_columns <- intersect(
        c("source_row_id", "PATID", "EVTID", "ELTID"),
        names(biol))
    for (column in id_columns) {
        biol[[column]] <- as.character(biol[[column]])
    }
    biol$.ee_point_date <- .clinical_date(biol[[date_col]])
    biol$.ee_analyte <- as.character(biol[[analyte_col]])


    # Grain is declared by the variable and carried by the task universe.
    tkeys <- tasks %>%
        transmute(task_id = as.character(task_id), PATID = as.character(PATID))
    for (key in setdiff(grain_keys, "PATID")) {
        tkeys[[key]] <- as.character(tasks[[key]])
    }
    if (windowed) tkeys$anchor_date <- .clinical_date(tasks$anchor_date)
    target_analytes <- toupper(trimws(as.character(analytes)))

    pre_selector <- biol %>%
        inner_join(tkeys, by = grain_keys, relationship = "many-to-many")

    scoped <- pre_selector
    if (windowed) {
        scoped <- scoped %>%
            filter(.within_point(.data$.ee_point_date,
                                 anchor_date + from_days,
                                 anchor_date + to_days))
    }
    observations <- scoped %>%
        mutate(field = field, source = source, in_scope = TRUE)
    analyte_match <- !is.na(observations$.ee_analyte) &
        toupper(trimws(observations$.ee_analyte)) %in% target_analytes

    observations$is_target <- analyte_match
    observations <- .apply_row_predicate(
        observations, filter_rows, field, source_columns)
    observations <- .apply_group_predicate(
        observations, group_by, filter_groups, field, source_columns)
    observations <- observations %>%
        mutate(
            selected_evidence = is_target,
            scope_reason = if (windowed) "point time inside the task window"
                           else "same grain unit (no window)",
            observation_reason = case_when(
                .data$is_target ~ "analyte matches the declared concept",
                .data$group_demoted ~ "group aggregate predicate not satisfied",
                .data$row_demoted ~ "row predicate not satisfied",
                analyte_match ~ "analyte match demoted by activation rules",
                TRUE ~ "analyte outside the declared concept"))


    # Candidates are task identity + the complete prepared source row. Reducers and
    # projections consume real column names rather than a hidden `value` alias.
    candidate_columns <- unique(c("task_id", source_columns))
    candidates <- observations %>%
        filter(is_target) %>%
        arrange(task_id, .data$.ee_point_date, source_row_id) %>%
        select(all_of(candidate_columns))

    # Evidence uses the same complete row and adds only stable engine provenance.
    evidence_columns <- unique(c(
        "task_id", "field", "source", "source_row_id", "evidence_ref",
        "evidence_summary", setdiff(source_columns, "source_row_id")))
    evidence <- observations %>%
        filter(selected_evidence) %>%
        mutate(
            evidence_ref = source_row_id,
            evidence_summary = sprintf(
                "%s on %s", .data$.ee_analyte, .data$.ee_point_date)) %>%
        select(all_of(evidence_columns))

    list(
        candidates = candidates,
        evidence = evidence,
        lineage_inputs = .structured_lineage_inputs(
            pre_selector, scoped, observations, windowed))
}
