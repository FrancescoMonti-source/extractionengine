# PROTOTYPE -- throwaway. The rule combinators: the part that would move into
# the engine. Nothing here knows about denutrition.
#
# A quantity turns one stay's kept facts into an interval [lo, hi]: a point when
# a fact measures it, [floor, Inf) when facts only bound it from below, NULL
# when no fact speaks to it. A criterion turns the same facts into "met",
# "not_met" or "unknown", and carries the ids of the facts that decided it.
#
# Comparing an interval with a threshold is three-valued without a special
# case: met when every point of the interval satisfies it, not_met when none
# does, unknown otherwise. A floor can therefore establish ">= 5" and never
# refute it, which is the rule redsan-coding wrote twice as `.compare_floor()`.
#
# Absence is never a refutation. A fact nobody extracted is not a negative, so
# `has()` answers met or unknown and nothing else; not_met needs a fact that
# says so -- a measured value on the wrong side, or a negated fact.

answer <- function(state, facts = character()) {
  list(state = state, facts = unique(facts[!is.na(facts)]))
}

quantity <- function(f) structure(list(f = f), class = "fl_quantity")
criterion <- function(f) structure(list(f = f), class = "fl_criterion")
evaluate <- function(node, ctx) node$f(ctx)

kleene_or <- function(s) {
  if (any(s == "met")) "met" else if (any(s == "unknown")) "unknown" else "not_met"
}
kleene_and <- function(s) {
  if (any(s == "not_met")) "not_met" else if (any(s == "unknown")) "unknown" else "met"
}

# --- quantities ------------------------------------------------------------

# One value per stay. `drop` removes facts unless it would remove them all;
# `prefer` narrows to a subset when that subset is not empty.
pick_value <- function(concept, how, drop, prefer) {
  quantity(function(ctx) {
    x <- ctx$facts[ctx$facts$concept == concept & !ctx$facts$negated, , drop = FALSE]
    if (!is.null(drop) && nrow(x)) {
      gone <- eval(drop, x, baseenv()) %in% TRUE
      if (!all(gone)) x <- x[!gone, , drop = FALSE]
    }
    if (!is.null(prefer) && nrow(x)) {
      keep <- eval(prefer, x, baseenv()) %in% TRUE
      if (any(keep)) x <- x[keep, , drop = FALSE]
    }
    if (!nrow(x)) return(NULL)
    i <- which(x$value == how(x$value))[[1L]]
    list(lo = x$value[[i]], hi = x$value[[i]], facts = x$fact_id[[i]])
  })
}
lowest <- function(concept, drop = NULL, prefer = NULL) {
  pick_value(concept, min, substitute(drop), substitute(prefer))
}
highest <- function(concept, drop = NULL, prefer = NULL) {
  pick_value(concept, max, substitute(drop), substitute(prefer))
}

# The largest change over a window, or against a reference. A fact whose span
# lies inside the window measures it; one whose span is only shorter bounds it
# from below, as does any fact that is itself a floor. A negated fact answers
# zero, and only for a stay where no change of any kind was stated: a
# measurement always outranks a denial.
change <- function(concept, window = NULL, against = NULL) {
  quantity(function(ctx) {
    all <- ctx$facts[ctx$facts$concept == concept, , drop = FALSE]
    if (!any(!all$negated)) {
      if (any(all$negated)) return(list(lo = 0, hi = 0, facts = all$fact_id[all$negated][[1L]]))
      return(NULL)
    }
    x <- all[!all$negated & all$unit %in% "%", , drop = FALSE]
    if (!is.null(window)) {
      x <- x[x$reference %in% "timed" & !is.na(x$span_hi) & x$span_hi <= window[[2L]], , drop = FALSE]
      spans <- x$bound == "exact" & x$span_lo >= window[[1L]]
    } else {
      x <- x[x$reference %in% against, , drop = FALSE]
      spans <- x$bound == "exact"
    }
    top <- function(rows) if (any(rows)) which(rows)[which.max(x$value[rows])] else integer()
    v <- top(spans)
    f <- top(!spans)
    if (!length(v) && !length(f)) return(NULL)
    value <- if (length(v)) x$value[[v]] else NA_real_
    floor <- if (length(f)) x$value[[f]] else NA_real_
    measured <- is.na(floor) || (!is.na(value) && value >= floor)
    lo <- max(value, floor, na.rm = TRUE)
    list(lo = lo, hi = if (measured) lo else Inf, facts = x$fact_id[c(v, f)])
  })
}

# --- criteria ----------------------------------------------------------------

compare <- function(q, op, threshold) {
  criterion(function(ctx) {
    m <- q$f(ctx)
    if (is.null(m)) return(answer("unknown"))
    t <- if (is.function(threshold)) threshold(ctx$stay) else threshold
    if (is.na(t)) return(answer("unknown", m$facts))
    at <- function(v) match.fun(op)(v, t)
    state <- if (at(m$lo) && at(m$hi)) "met" else if (!at(m$lo) && !at(m$hi)) "not_met" else "unknown"
    answer(state, m$facts)
  })
}

Ops.fl_quantity <- function(e1, e2) {
  flip <- c("<" = ">", "<=" = ">=", ">" = "<", ">=" = "<=")
  if (!.Generic %in% names(flip)) stop("A quantity compares with <, <=, > or >=.", call. = FALSE)
  if (inherits(e1, "fl_quantity")) compare(e1, .Generic, e2) else compare(e2, flip[[.Generic]], e1)
}

# A closed band, said the way the fiche says it: `from` is >=, `above` is >,
# `below` is <, `upto` is <=.
band <- function(q, from = NULL, above = NULL, below = NULL, upto = NULL, upper_unless_refuted = FALSE) {
  criterion(function(ctx) {
    m <- q$f(ctx)
    if (is.null(m)) return(answer("unknown"))
    fixed <- quantity(function(ctx) m)
    side <- function(op, t) if (is.null(t)) "met" else evaluate(compare(fixed, op, t), ctx)$state
    lower <- if (!is.null(from)) side(">=", from) else side(">", above)
    upper <- if (!is.null(below)) side("<", below) else side("<=", upto)
    if (upper_unless_refuted && is.infinite(m$hi) && upper == "unknown") upper <- "met"
    answer(kleene_and(c(lower, upper)), m$facts)
  })
}

any_of <- function(...) {
  parts <- list(...)
  criterion(function(ctx) {
    r <- lapply(parts, evaluate, ctx)
    s <- vapply(r, `[[`, "", "state")
    state <- kleene_or(s)
    decided <- switch(state, met = r[s == "met"], unknown = r[s == "unknown"], not_met = r)
    answer(state, unlist(lapply(decided, `[[`, "facts")))
  })
}

all_of <- function(...) {
  parts <- list(...)
  criterion(function(ctx) {
    r <- lapply(parts, evaluate, ctx)
    s <- vapply(r, `[[`, "", "state")
    state <- kleene_and(s)
    decided <- switch(state, not_met = r[s == "not_met"], unknown = r[s == "unknown"], met = r)
    answer(state, unlist(lapply(decided, `[[`, "facts")))
  })
}

# Does an affirmed fact exist -- or `at_least` of them, counted over distinct
# values of `distinct` when it is given? Negated, hypothetical and family facts
# never count; `where` says what else must hold. Presence-only: met or unknown,
# since too few facts is not a refutation either.
has <- function(concepts, where = NULL, at_least = 1L, distinct = NULL) {
  where <- substitute(where)
  distinct <- substitute(distinct)
  env <- parent.frame()
  criterion(function(ctx) {
    f <- ctx$facts
    x <- f[f$concept %in% concepts & !f$negated & !f$hypothetical & !f$family, , drop = FALSE]
    if (!is.null(where) && nrow(x)) x <- x[eval(where, x, env) %in% TRUE, , drop = FALSE]
    k <- if (is.null(distinct)) nrow(x) else length(unique(eval(distinct, x, env)))
    if (nrow(x) && k >= at_least) answer("met", x$fact_id) else answer("unknown")
  })
}

# The model's own judgement of this criterion, read from where the grid puts
# it. The one place a rule reads an answer instead of computing one.
judged <- function() {
  criterion(function(ctx) {
    f <- ctx$facts
    x <- f[f$concept == paste0("judgement:", ctx$path) & f$asserted_by == "model", , drop = FALSE]
    if (!nrow(x)) return(answer("unknown"))
    answer(x$value_chr[[1L]], x$fact_id[[1L]])
  })
}

# --- a grid ------------------------------------------------------------------

band_rules <- function(age, ...) list(age = age, axes = list(...))

# Every named criterion of the stay's band, then each axis as the disjunction of
# its criteria. One row per criterion, with the facts that decided it.
evaluate_band <- function(bands, stay, facts) {
  hit <- vapply(bands, function(b) stay$age >= b$age[[1L]] && stay$age < b$age[[2L]], NA)
  band <- names(bands)[hit][[1L]]
  rows <- list()
  for (axis in names(bands[[band]]$axes)) {
    for (name in names(bands[[band]]$axes[[axis]])) {
      ctx <- list(stay = stay, facts = facts, path = paste(axis, name, sep = "."))
      a <- evaluate(bands[[band]]$axes[[axis]][[name]], ctx)
      rows[[length(rows) + 1L]] <- data.frame(
        EVTID = stay$EVTID, band = band, axis = axis,
        criterion = paste(band, axis, name, sep = "."), state = a$state,
        facts = paste(a$facts, collapse = ","), stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}
