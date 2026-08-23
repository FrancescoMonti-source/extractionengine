# =============================================================================
# channel-cache.R — reusing a text activation across the variables of a protocol
# -----------------------------------------------------------------------------
# Two variables of one study often activate the same text channel: the same
# query, over the same corpus snapshot, for the same units. Each used to pay for
# its own Lucene retrieval and, on the LLM path, its own model call per task.
# The model call is the saving that matters; Phase 4.5 already measured that the
# deterministic executor is noise beside it.
#
# ONLY the text branch is cached. The Phase 1 profile put the structured
# executor at 2.1 % of a membership run, so caching it would buy ~2 % in
# exchange for a real correctness surface on the key. That half is cut
# deliberately, not forgotten.
# =============================================================================

.channel_cache <- function(sources) {
    cache <- attr(sources, "ee_channel_cache")
    if (is.environment(cache)) cache else NULL
}

# One environment for the whole protocol, carried on the prepared bundle beside
# the roster and the snapshot identity. An environment is shared by reference,
# so every variable of the run sees the same entries even though each gets its
# own copy of the source list.
.attach_channel_cache <- function(sources) {
    if (is.null(sources) || is.environment(attr(sources, "ee_channel_cache"))) {
        return(sources)
    }
    attr(sources, "ee_channel_cache") <- new.env(parent = emptyenv())
    sources
}

# Is this name bound, in the authoring environment, to a function the author
# wrote? A function reached in a package namespace, on the search path, or in
# base is part of the installed runtime that `manifest$runtime` already pins, and
# its body cannot change between two activations of one protocol. Anything else
# can.
.is_authored_function <- function(env, name) {
    binding_env <- env
    while (!identical(binding_env, emptyenv())) {
        if (rlang::env_has(binding_env, name, inherit = FALSE)) {
            if (rlang::env_binding_are_active(binding_env, name) ||
                rlang::env_binding_are_lazy(binding_env, name)) {
                return(FALSE)
            }
            if (!is.function(rlang::env_get(binding_env, name, inherit = FALSE))) {
                return(FALSE)
            }
            return(!rlang::is_namespace(binding_env) &&
                   !identical(binding_env, baseenv()) &&
                   !environmentName(binding_env) %in% search())
        }
        binding_env <- rlang::env_parent(binding_env)
    }
    FALSE
}

# The Phase 1.3 rule makes a name whose nearest ordinary binding is a function
# invisible to `.data_mask_references()` -- author code is not data -- and that
# walker never visits a call head at all. Both are right for validation and
# wrong for a cache key, because `.manifest_snapshot()` renders the expression
# TEXT: two activations reading `helper(hit_text)` with different `helper`
# bodies render identically and would hash identically. An invisible dependency
# is not an identifiable one.
#
# Every symbol is visited, call heads included. Over-collecting only refuses a
# cache entry; under-collecting would serve one activation's answers for another.
.authored_function_dependencies <- function(quosure) {
    env <- rlang::quo_get_env(quosure)
    found <- character()
    visit <- function(node) {
        if (rlang::is_symbol(node)) {
            name <- rlang::as_string(node)
            if (nzchar(name) && .is_authored_function(env, name)) {
                found <<- c(found, name)
            }
        } else if (rlang::is_call(node)) {
            for (part in as.list(node)) visit(part)
        }
        invisible(NULL)
    }
    visit(rlang::quo_get_expr(quosure))
    unique(found)
}

# The external values an activation's own expressions read. NULL means the
# activation is NOT cacheable: a value that was not photographed cannot be
# quoted in a key, so a hit might serve a result computed under a different one.
# This is the plan's rule -- an unidentifiable dependency is not cached -- and
# it falls straight out of the parameter photograph, plus the authored functions
# the photograph cannot see.
.channel_cache_parameters <- function(channel_def) {
    values <- list()
    identifiable <- TRUE
    collect <- function(quosure) {
        env <- rlang::quo_get_env(quosure)
        if (length(.authored_function_dependencies(quosure))) {
            identifiable <<- FALSE
        }
        for (key in .data_mask_references(quosure)$external) {
            value <- rlang::env_get(env, key, inherit = TRUE)
            if (.is_simple_parameter(value)) {
                values[[key]] <- value
            } else {
                identifiable <<- FALSE
            }
        }
        quosure
    }
    .map_spec_quosures(channel_def, collect)
    if (identifiable) values else NULL
}

# The key is a hash of everything the activation reads, not a hand-listed set of
# fields: `.manifest_snapshot()` renders the whole resolved channel -- including
# an argument `use_channel()` does not have yet -- as plain data, and the frozen
# parameters supply the values its expression text cannot show. The output grain
# is part of the key because it reaches the model prompt through
# format_task_target(). Anything that cannot be rendered leaves the activation
# uncacheable rather than keyed on a guess.
.channel_cache_key <- function(variable, channel_def, tasks, sources, chat,
                               grain_keys, cohort_tasks) {
    snapshot <- attr(sources, "ee_source_identity")[[channel_def$source]]$digest
    if (is.null(snapshot)) return(NULL)
    parameters <- .channel_cache_parameters(channel_def)
    if (is.null(parameters)) return(NULL)
    metadata <- if (is.null(chat)) list() else {
        tryCatch(.chat_metadata(chat), error = function(cnd) NULL)
    }
    if (is.null(metadata)) return(NULL)
    tryCatch(
        rlang::hash(list(
            snapshot = snapshot,
            channel = .manifest_snapshot(channel_def),
            parameters = parameters,
            group_by = variable$output$group_by,
            grain_keys = grain_keys,
            tasks = tasks,
            cohort_tasks = cohort_tasks,
            chat = metadata)),
        error = function(cnd) NULL)
}

# A reused result records that its model calls were made earlier in this run.
# Republishing them unmarked would let a protocol's call count double, claiming
# work -- and cost -- that never happened a second time.
.reused_channel_result <- function(result) {
    result$reused <- TRUE
    result
}
