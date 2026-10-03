# PROTOTYPE -- throwaway. One shape for every fact, whoever produced it.
#
# A fact is one thing a record says about one patient. The biology table, the
# PMSI, a model reading a letter, a regular expression and a rule computing from
# other facts all emit rows of the same table; `producer` tells them apart and
# nothing downstream branches on it.
#
# Needs `redsancoding` internals loaded (run.R does it): the evidence index
# `.denut_model_input()`, and the number and duration grounding checks.

FACT_PROTO <- list(
  fact_id = character(), PATID = character(), EVTID = character(),
  concept = character(),
  value = double(), unit = character(), value_chr = character(),
  # "exact", or "lower" when the value is only a floor on the quantity.
  bound = character(),
  record_date = as.Date(character()),
  # What the value is relative to. A weight: "current", "compared" (the later
  # weight of a comparison), "earlier", "usual", "before_disease". A change:
  # "timed", "usual", "before_disease". NA for a value that stands alone.
  reference = character(),
  # For a timed change: bounds on the days it spans. The grid's windows read
  # these, never the words they came from.
  span_lo = double(), span_hi = double(),
  negated = logical(), hypothetical = logical(), historical = logical(), family = logical(),
  # For a condition: "active" or "stable" when the record says which, and when
  # it began relative to admission ("before_admission", "at_admission",
  # "during_stay", "unknown"). NA when the producer cannot tell.
  activity = character(), onset = character(),
  # Who made the statement: "record" (the document says it), "dietitian",
  # "coder", or "model" (a judgement the model made, not one it read).
  asserted_by = character(),
  # "measured" (a structured row), "stated" (read from text), "derived"
  # (computed by a rule from other facts), "judged" (a judgement).
  derivation = character(),
  source = character(), producer = character(), producer_version = character(),
  status = character(), reason = character(),
  # Presentation only: a rationale or a calculation. No rule reads it.
  note = character()
)

EVIDENCE_PROTO <- list(
  fact_id = character(),
  # "source_row", "fragment" (a citable fragment of a document), or "fact".
  kind = character(),
  ELTID = character(), record_ref = character(), fragment_id = character(),
  quote = character(), parent_fact_id = character()
)

.ids <- new.env()
.ids$n <- 0L
new_ids <- function(k) {
  ids <- .ids$n + seq_len(k)
  .ids$n <- .ids$n + k
  sprintf("F%05d", ids)
}

# Rows of the fact table with the defaults every producer shares.
facts_frame <- function(...) {
  x <- list(...)
  n <- max(c(0L, lengths(x)))
  defaults <- list(
    bound = "exact", negated = FALSE, hypothetical = FALSE, historical = FALSE,
    family = FALSE, asserted_by = "record", status = "kept"
  )
  cols <- lapply(names(FACT_PROTO), function(nm) {
    v <- x[[nm]] %||% defaults[[nm]]
    proto <- FACT_PROTO[[nm]]
    if (is.null(v)) return(rep(proto[NA_integer_], n))
    if (inherits(proto, "Date")) v <- as.Date(v)
    rep_len(v, n)
  })
  names(cols) <- names(FACT_PROTO)
  as.data.frame(cols, stringsAsFactors = FALSE)
}

evidence_frame <- function(...) {
  x <- list(...)
  n <- max(c(0L, lengths(x)))
  cols <- lapply(names(EVIDENCE_PROTO), function(nm) {
    v <- x[[nm]]
    if (is.null(v)) rep(NA_character_, n) else rep_len(as.character(v), n)
  })
  names(cols) <- names(EVIDENCE_PROTO)
  as.data.frame(cols, stringsAsFactors = FALSE)
}

empty_facts <- function() facts_frame()[0, ]
empty_evidence <- function() evidence_frame()[0, ]

`%||%` <- function(a, b) if (is.null(a)) b else a
nz <- function(x) ifelse(is.na(x), "", x)

bind_parts <- function(parts) {
  list(
    facts = do.call(rbind, c(list(empty_facts()), lapply(parts, `[[`, "facts"))),
    evidence = do.call(rbind, c(list(empty_evidence()), lapply(parts, `[[`, "evidence")))
  )
}

fold <- function(x) tolower(iconv(x, "UTF-8", "ASCII//TRANSLIT"))

# Fragments cited by a model, as evidence rows of one fact.
cited <- function(fact_id, ev) {
  if (is.null(ev) || !nrow(ev)) return(empty_evidence())
  evidence_frame(
    fact_id = fact_id, kind = ifelse(is.na(ev$evidence_id), "source_row", "fragment"),
    ELTID = ev$ELTID, record_ref = ev$prompt_record_id, fragment_id = ev$evidence_id,
    quote = ev$quote
  )
}

parents <- function(fact_id, parent_ids) {
  evidence_frame(fact_id = fact_id, kind = "fact", parent_fact_id = parent_ids)
}

# ---------------------------------------------------------------------------
# The stay: the index the rules read beside the facts. Not a fact itself, as
# OMOP keeps the person and the visit out of the measurement table.
# ---------------------------------------------------------------------------

stay_of <- function(bundle) {
  m <- bundle$sources$pmsi$main
  data.frame(
    EVTID = bundle$event_id, PATID = m$PATID[[1L]],
    age = as.numeric(unique(m$PATAGE)[[1L]]), sex = unique(m$PATSEX)[[1L]],
    admission = if (all(is.na(m$DATENT))) as.Date(NA) else as.Date(min(m$DATENT, na.rm = TRUE)),
    discharge = if (all(is.na(m$DATSORT))) as.Date(NA) else as.Date(max(m$DATSORT, na.rm = TRUE)),
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Structured producers
# ---------------------------------------------------------------------------

# Gap 1: albumin is a concept defined by a predicate over biology rows, not by a
# code list. The predicate is `.select_albumin()`'s, transcribed. A row the label
# selects but the unit or the plausibility bounds refuse becomes a refused fact,
# visible with its reason, instead of disappearing.
ALBUMIN_LABEL <- "albumin"
ALBUMIN_EXCLUDE <- "pr.{0,2}alb|micro|urin|\\bLCR\\b|quotient|volume|glyc|ratio|ascite|pleural"

facts_biology <- function(bundle, stay) {
  biol <- bundle$sources$biol
  if (is.null(biol) || !nrow(biol)) return(bind_parts(list()))
  label <- biol$TYPEANA_LABEL
  albumin <- which(!is.na(label) & grepl(ALBUMIN_LABEL, label, ignore.case = TRUE) &
    !grepl(ALBUMIN_EXCLUDE, label, ignore.case = TRUE, perl = TRUE))
  crp <- which(biol$TYPEANA %in% "CRP.CRP")
  one <- function(rows, concept, unit_ok, bounds, unit) {
    if (!length(rows)) return(NULL)
    value <- as.numeric(biol$NUMRES[rows])
    reason <- ifelse(is.na(value), "no numeric result",
      ifelse(is.na(biol$UNITE[rows]) | !grepl(unit_ok, biol$UNITE[rows], ignore.case = TRUE),
        paste0("unit is not ", unit),
        ifelse(value < bounds[[1L]] | value > bounds[[2L]],
          sprintf("outside plausible %g-%g %s", bounds[[1L]], bounds[[2L]], unit), NA_character_)))
    ids <- new_ids(length(rows))
    list(
      facts = facts_frame(
        fact_id = ids, PATID = stay$PATID, EVTID = stay$EVTID, concept = concept,
        value = value, unit = unit, value_chr = biol$TYPEANA[rows],
        record_date = as.Date(biol$DATEXAM[rows]), derivation = "measured",
        source = "biol", producer = "biology-selector", producer_version = "proto-1",
        status = ifelse(is.na(reason), "kept", "refused"), reason = reason,
        note = biol$TYPEANA_LABEL[rows]
      ),
      evidence = evidence_frame(
        fact_id = ids, kind = "source_row", ELTID = biol$ELTID[rows],
        record_ref = sprintf("BIO-%04d", rows),
        quote = paste(biol$NUMRES[rows], biol$UNITE[rows])
      )
    )
  }
  bind_parts(Filter(Negate(is.null), list(
    one(albumin, "albumin", "^g\\s*/\\s*l$", c(5, 60), "g/L"),
    one(crp, "crp", "^mg\\s*/\\s*l$", c(0, 1000), "mg/L")
  )))
}

# Closed-list concepts as ICD-10 sets, under the same names the model producer
# uses (atomic.R). Built only for the concepts this study asks about. E40-E46
# are never read: they are the code under audit. A code is a condition managed
# during the stay, so its activity is "active"; the code itself is the stage
# when it carries one (N18.4, N18.5).
ICD10_SETS <- c(
  sepsis = "^(A4[01]|R572|R651)",
  diabetic_crisis = "^E1[0-4][01]",
  deep_infection = "^(I33|M86|M46[2-5]|M00|T845)",
  malignancy = "^C[0-9]",
  dialysis = "^(Z992|Z49)",
  chronic_kidney_disease = "^N18[45]",
  cirrhosis = "^(K703|K717|K74[456])",
  chronic_infection = "^A1[5-9]",
  # Recorded so a reader sees them, and read by no rule: a chronic respiratory
  # failure without long-term oxygen, a heart failure without its stage, a
  # stroke and a pancreatitis without its severity do not establish the
  # aggression on the closed list.
  chronic_respiratory_failure = "^J961",
  heart_failure = "^I50",
  stroke = "^I6[134]",
  acute_pancreatitis = "^K85"
)

# Major surgery from the CCAM label, the same move as albumin: a label
# predicate where no code list was written.
CCAM_MAJOR_SURGERY <- paste(
  "colectomie|gastrectomie|hepatectomie|pancreatectomie|oesophagectomie|proctectomie",
  "resection [a-z ]{0,25}(intestin|grele|colon|rectum|estomac|oesophage|jejunum|ileon)",
  "amputation du rectum|pontage aortocoronarien|pontage coronaire|lobectomie pulmonaire",
  "pneumonectomie|transplantation|greffe d[eu] (rein|foie|coeur|poumon)",
  sep = "|"
)

facts_pmsi <- function(bundle, stay) {
  parts <- list()
  dg <- bundle$sources$pmsi$diag
  if (!is.null(dg) && nrow(dg)) {
    code <- gsub("[^A-Z0-9]", "", toupper(dg$diag))
    for (concept in names(ICD10_SETS)) {
      rows <- which(grepl(ICD10_SETS[[concept]], code))
      if (!length(rows)) next
      ids <- new_ids(length(rows))
      parts[[length(parts) + 1L]] <- list(
        facts = facts_frame(
          fact_id = ids, PATID = stay$PATID, EVTID = stay$EVTID, concept = concept,
          value_chr = code[rows], record_date = as.Date(dg$DATSORT[rows]), activity = "active",
          asserted_by = "coder", derivation = "measured", source = "pmsi_diag",
          producer = "pmsi-icd10-sets", producer_version = "proto-1", note = dg$type_diag[rows]
        ),
        evidence = evidence_frame(
          fact_id = ids, kind = "source_row", ELTID = dg$ELTID[rows],
          record_ref = sprintf("DIAG-%04d", rows), quote = paste(code[rows], dg$CODE_LABEL[rows])
        )
      )
    }
  }
  ac <- bundle$sources$pmsi$actes
  if (!is.null(ac) && nrow(ac)) {
    rows <- which(grepl(CCAM_MAJOR_SURGERY, fold(ac$CODEACTE_LABEL), perl = TRUE))
    if (length(rows)) {
      ids <- new_ids(length(rows))
      parts[[length(parts) + 1L]] <- list(
        facts = facts_frame(
          fact_id = ids, PATID = stay$PATID, EVTID = stay$EVTID, concept = "major_surgery",
          value_chr = ac$CODEACTE[rows], record_date = as.Date(ac$DATEACTE[rows]),
          asserted_by = "coder", derivation = "measured", source = "pmsi_actes",
          producer = "ccam-label-selector", producer_version = "proto-1"
        ),
        evidence = evidence_frame(
          fact_id = ids, kind = "source_row", ELTID = ac$ELTID[rows],
          record_ref = sprintf("ACT-%04d", rows), quote = paste(ac$CODEACTE[rows], ac$CODEACTE_LABEL[rows])
        )
      )
    }
  }
  bind_parts(parts)
}

# ---------------------------------------------------------------------------
# Text producer 1: the luna run. Its quantitative candidates are already
# fact-shaped; computed ones are split into the facts they were computed from
# and a derived fact citing them. Its narrative criteria are judgements, and
# enter as judgement facts asserted by the model -- the part this shape is
# meant to replace.
# ---------------------------------------------------------------------------

ONE_MONTH <- "(?<![0-9])(?:1\\s*mois|un\\s*mois|(?:30|31)\\s*(?:jours?|j\\b))"
SIX_MONTHS <- "(?<![0-9])(?:6\\s*mois|six\\s*mois|(?:180|181|182|183|184)\\s*(?:jours?|j\\b))"
SUB_WINDOW <- "(?:moins\\s+d['e]|<|inf[eé]rieur)"

# The time model of a timed change: bounds on the days it spans, read once from
# the category the model filed it under and the duration it transcribed. The
# text can only narrow the category, never contradict it.
span_of <- function(category, text, elapsed) {
  if (!is.na(elapsed)) return(c(elapsed, elapsed))
  if (is.na(category) || !category %in% c("within_1m", "within_6m", "over_6m") ||
    is.na(text) || !nzchar(trimws(text))) {
    return(c(NA_real_, NA_real_))
  }
  if (category == "over_6m") return(c(184, Inf))
  hi <- if (category == "within_1m") 31 else 183
  exact <- !grepl(SUB_WINDOW, text, ignore.case = TRUE, perl = TRUE)
  lo <- if (exact && category == "within_1m" && grepl(ONE_MONTH, text, ignore.case = TRUE, perl = TRUE)) {
    28
  } else if (exact && category == "within_6m" && grepl(SIX_MONTHS, text, ignore.case = TRUE, perl = TRUE)) {
    180
  } else {
    0
  }
  c(lo, hi)
}

reference_of <- function(comparison, category) {
  ifelse(comparison %in% "before_disease" | category %in% "before_disease", "before_disease",
    ifelse(comparison %in% "usual" | category %in% "usual_without_duration", "usual",
      ifelse(comparison %in% "timed" | category %in% c("within_1m", "within_6m", "over_6m"), "timed",
        NA_character_)))
}

# The grounding rule, now a property of the fact layer rather than of one
# pipeline: a number read from text must be in the text cited for it.
grounded <- function(value, quotes, height = FALSE) {
  if (is.na(value)) return(TRUE)
  if (!height) return(.value_read_from(value, quotes))
  any(vapply(c(1, 100, 0.01), function(s) .value_read_from(value * s, quotes), NA)) ||
    .height_written_as_metres(value, quotes)
}

NARRATIVE <- c(
  "phenotypic.muscle", "phenotypic.channel", "etiologic.intake", "etiologic.absorption",
  "etiologic.aggression", "moderate.channel", "severe.channel", "severe.stature"
)

facts_luna <- function(run, stay, index, producer) {
  version <- paste(unique(run$assessments$model), substr(unique(run$assessments$code_digest), 1, 8))
  date_of <- function(ev) {
    d <- as.Date(index$source_date[match(ev$evidence_id, index$evidence_id)])
    if (all(is.na(d))) as.Date(NA) else min(d, na.rm = TRUE)
  }
  base <- function(...) facts_frame(
    PATID = stay$PATID, EVTID = stay$EVTID, source = "doceds", producer = producer,
    producer_version = version, ...
  )
  parts <- list()
  add <- function(facts, evidence) parts[[length(parts) + 1L]] <<- list(facts = facts, evidence = evidence)
  check <- function(ok, what) if (ok) list(status = "kept", reason = NA_character_) else
    list(status = "refused", reason = paste(what, "does not appear in any fragment cited for it"))

  mc <- run$metric_candidates[run$metric_candidates$EVTID == stay$EVTID, , drop = FALSE]
  for (i in seq_len(nrow(mc))) {
    r <- mc[i, , drop = FALSE]
    ev <- r$evidence[[1L]]
    q <- ev$quote
    when <- date_of(ev)
    historical <- r$temporal_role %in% "historical"
    if (r$metric == "bmi" && r$derivation == "stated") {
      id <- new_ids(1L)
      g <- check(grounded(r$value, q), "the BMI")
      add(base(fact_id = id, concept = "bmi", value = r$value, unit = "kg/m2", record_date = when,
        reference = "current", historical = historical, derivation = "stated",
        status = g$status, reason = g$reason, note = r$rationale), cited(id, ev))
    } else if (r$metric == "bmi") {
      # A computed BMI is three facts: the weight and the height the model read
      # together, and the BMI a rule derived from them. The derived fact cites
      # the two facts, and they cite the text.
      op <- as.numeric(regmatches(r$calculation, regexec("^([0-9.]+) / ([0-9.]+)\\^2", r$calculation))[[1L]][2:3])
      if (anyNA(op)) stop("Unparsed BMI calculation.", call. = FALSE)
      ids <- new_ids(3L)
      gw <- check(grounded(op[[1L]], q), "the weight")
      gh <- check(grounded(op[[2L]], q, height = TRUE), "the height")
      add(base(fact_id = ids[[1L]], concept = "weight", value = op[[1L]], unit = "kg", record_date = when,
        reference = "current", historical = historical, derivation = "stated",
        status = gw$status, reason = gw$reason), cited(ids[[1L]], ev))
      add(base(fact_id = ids[[2L]], concept = "height", value = op[[2L]] * 100, unit = "cm",
        record_date = when, derivation = "stated", status = gh$status, reason = gh$reason), cited(ids[[2L]], ev))
      ok <- gw$status == "kept" && gh$status == "kept"
      add(base(fact_id = ids[[3L]], concept = "bmi", value = r$value, unit = "kg/m2", record_date = when,
        reference = "current", historical = historical, derivation = "derived",
        source = "facts", producer = "rule:bmi", producer_version = "proto-1",
        status = if (ok) "kept" else "refused", reason = if (ok) NA else "an operand was refused",
        note = r$calculation), parents(ids[[3L]], ids[1:2]))
    } else if (r$derivation == "documented_absence") {
      id <- new_ids(1L)
      add(base(fact_id = id, concept = "weight_loss", negated = TRUE, record_date = when,
        derivation = "stated", note = r$rationale), cited(id, ev))
    } else {
      reference <- reference_of(r$comparison, r$duration_category)
      span <- if (reference %in% "timed") span_of(r$duration_category, r$duration_text, r$elapsed_days) else c(NA, NA)
      timed_text_ok <- !reference %in% "timed" || is.na(r$duration_text) ||
        .duration_read_from(r$duration_text, q)
      if (r$derivation == "stated") {
        id <- new_ids(1L)
        g <- check(grounded(r$value, q) && timed_text_ok, "the loss or its duration")
        add(base(fact_id = id, concept = "weight_loss", value = r$value, unit = r$unit,
          record_date = when, reference = reference, span_lo = span[[1L]], span_hi = span[[2L]],
          derivation = "stated", status = g$status, reason = g$reason,
          note = paste0(nz(r$duration_text), " | ", r$rationale)), cited(id, ev))
      } else {
        # Two weights the record compares, and the loss a rule derived.
        op <- as.numeric(regmatches(r$calculation,
          regexec("^\\(([0-9.]+)(?: \\[avant maladie\\])? - ([0-9.]+)\\)", r$calculation, perl = TRUE))[[1L]][2:3])
        if (anyNA(op)) stop("Unparsed weight-change calculation.", call. = FALSE)
        ids <- new_ids(3L)
        earlier <- if (reference %in% "timed") "earlier" else reference
        gr <- check(grounded(op[[1L]], q), "the reference weight")
        gc <- check(grounded(op[[2L]], q), "the compared weight")
        add(base(fact_id = ids[[1L]], concept = "weight", value = op[[1L]], unit = "kg",
          record_date = when, reference = earlier, derivation = "stated",
          status = gr$status, reason = gr$reason), cited(ids[[1L]], ev))
        add(base(fact_id = ids[[2L]], concept = "weight", value = op[[2L]], unit = "kg",
          record_date = when, reference = "compared", derivation = "stated",
          status = gc$status, reason = gc$reason), cited(ids[[2L]], ev))
        ok <- gr$status == "kept" && gc$status == "kept" && timed_text_ok
        add(base(fact_id = ids[[3L]], concept = "weight_loss", value = r$value, unit = "%",
          record_date = when, reference = reference, span_lo = span[[1L]], span_hi = span[[2L]],
          derivation = "derived", source = "facts", producer = "rule:weight_change",
          producer_version = "proto-1", status = if (ok) "kept" else "refused",
          reason = if (ok) NA else "an operand or the duration was refused",
          note = paste0(nz(r$duration_text), " | ", r$calculation)), parents(ids[[3L]], ids[1:2]))
      }
    }
  }

  # What the run refused stays a fact, refused, with its reason and its
  # citation: the refusal contract is a status, not a deletion.
  rf <- run$refused_candidates[run$refused_candidates$EVTID == stay$EVTID, , drop = FALSE]
  for (i in seq_len(nrow(rf))) {
    id <- new_ids(1L)
    concept <- if (grepl("bmi", rf$group[[i]])) "bmi" else "weight_loss"
    add(base(fact_id = id, concept = concept, record_date = date_of(rf$evidence[[i]]),
      derivation = "stated", status = "refused", reason = rf$reason[[i]],
      note = paste(rf$group[[i]], rf$values[[i]], sep = " | ")), cited(id, rf$evidence[[i]]))
  }

  cr <- run$criteria[run$criteria$EVTID == stay$EVTID, , drop = FALSE]
  cr <- cr[sub("^[^.]+[.]", "", cr$criterion) %in% NARRATIVE, , drop = FALSE]
  for (i in seq_len(nrow(cr))) {
    id <- new_ids(1L)
    add(base(fact_id = id, concept = paste0("judgement:", sub("^[^.]+[.]", "", cr$criterion[[i]])),
      value_chr = cr$assessment[[i]], asserted_by = "model", derivation = "judged",
      note = cr$rationale[[i]]), cited(id, cr$evidence[[i]]))
  }
  bind_parts(parts)
}

# ---------------------------------------------------------------------------
# Text producer 2: a regular expression over the same fragments the model was
# shown, citing them by the same ids. Deterministic, so grounded by
# construction; its qualifiers come from a few words before the match.
# ---------------------------------------------------------------------------

LEXICON <- c(
  nyha_class = "nyha\\W{0,12}(?:classe|stade)?\\W{0,3}(iv|iii|ii|i|[1-4])\\b|(?:classe|stade)\\W{0,3}(iv|iii|ii|i|[1-4])\\W{0,8}(?:de la |de )?nyha",
  sepsis = "\\bsepsis\\b|\\bchoc septique",
  dialysis = "\\b(?:hemo)?dialys|epuration extra.?renale",
  cirrhosis = "\\bcirrhose",
  antituberculous_drug = "\\b(rifampicine|isoniazide|ethambutol|pyrazinamide|rifater|rifinah|rimifon|myambutol|dexambutol)\\b"
)
NEGATION <- "(?:\\bpas d[e']|\\babsence d[e']|\\bsans\\b|\\baucune?\\b|\\bni\\b|\\bnon\\b|\\belimine|\\becarte|\\bnegati)"
HYPOTHESIS <- "(?:\\bsuspicion|\\bsuspect|\\bpossible|\\bprobable|\\bevoque|\\ba eliminer|\\ba rechercher|\\beventuel|\\brisque d)"
HISTORY <- "(?:\\bantecedent|\\batcd\\b|\\bancien|\\bhistoire de)"
FAMILY <- "(?:\\bmere\\b|\\bpere\\b|\\bfrere|\\bsoeur|\\bfamilia|\\bfamille)"
ROMAN <- c("1" = "I", "2" = "II", "3" = "III", "4" = "IV", i = "I", ii = "II", iii = "III", iv = "IV")

facts_lexicon <- function(stay, index, docs_type) {
  doc <- startsWith(index$prompt_record_id, "DOC-")
  ix <- index[doc, , drop = FALSE]
  text <- fold(ix$quote)
  parts <- list()
  emit <- function(rows, concept, value_chr, qual, asserted_by = "record") {
    ids <- new_ids(length(rows))
    parts[[length(parts) + 1L]] <<- list(
      facts = facts_frame(
        fact_id = ids, PATID = stay$PATID, EVTID = stay$EVTID, concept = concept,
        value_chr = value_chr, record_date = as.Date(ix$source_date[rows]),
        negated = qual$negated, hypothetical = qual$hypothetical, historical = qual$historical,
        family = qual$family, asserted_by = asserted_by, derivation = "stated", source = "doceds",
        producer = "lexicon", producer_version = "proto-1"
      ),
      evidence = evidence_frame(
        fact_id = ids, kind = "fragment", ELTID = ix$ELTID[rows],
        record_ref = ix$prompt_record_id[rows], fragment_id = ix$evidence_id[rows], quote = ix$quote[rows]
      )
    )
  }
  for (concept in names(LEXICON)) {
    m <- regexpr(LEXICON[[concept]], text, perl = TRUE)
    rows <- which(m > 0)
    if (!length(rows)) next
    hit <- regmatches(text, m)
    before <- substr(text[rows], pmax(1L, m[rows] - 60L), m[rows] - 1L)
    before <- sub("^.*[.;:!]", "", before)
    after <- substr(text[rows], m[rows] + attr(m, "match.length")[rows], m[rows] + attr(m, "match.length")[rows] + 12L)
    # A year older than the admission near the match dates the mention to the
    # past: "sepsis sur materiel en 2018" is history, whatever words surround it.
    near <- substr(text[rows], pmax(1L, m[rows] - 80L), m[rows] + attr(m, "match.length")[rows] + 80L)
    admitted <- as.integer(format(stay$admission, "%Y"))
    dated_before <- vapply(regmatches(near, gregexpr("\\b(19|20)[0-9]{2}\\b", near, perl = TRUE)),
      function(y) !is.na(admitted) && length(y) > 0L && any(as.integer(y) < admitted), NA)
    qual <- list(
      negated = grepl(NEGATION, before, perl = TRUE),
      hypothetical = grepl(HYPOTHESIS, before, perl = TRUE) | grepl("^[^.]{0,6}\\?", after, perl = TRUE),
      historical = grepl(HISTORY, before, perl = TRUE) | dated_before,
      family = grepl(FAMILY, before, perl = TRUE)
    )
    value <- switch(concept,
      nyha_class = paste("NYHA", unname(ROMAN[sub("^.*?(iv|iii|ii|i|[1-4])\\b.*$", "\\1", hit, perl = TRUE)])),
      sepsis = ifelse(grepl("choc", hit), "septic_shock", "sepsis"),
      antituberculous_drug = hit,
      concept
    )
    # A NYHA class is the stage of a heart failure, filed where the model files it.
    emit(rows, if (concept == "nyha_class") "heart_failure" else concept, value, qual)
  }
  # The dietitian's box: a clinician's judgement, written in the record, and
  # recorded as hers. The CORA fiche prints a ticked box as
  # "(present) Situation d'agression" on one line.
  box <- which(docs_type[ix$prompt_record_id] %in% "FICHE_DIET" &
    grepl("\\(present\\)\\s*situation d.agression", text))
  if (length(box)) {
    no <- rep(FALSE, length(box))
    emit(box, "box:aggression", "present",
      list(negated = no, hypothetical = no, historical = no, family = no), asserted_by = "dietitian")
  }
  bind_parts(parts)
}

# ---------------------------------------------------------------------------
# A stage is a fact or it is nothing. What a model writes in a rationale about
# a NYHA class or a GOLD stage, read as the fact it would have had to emit, and
# grounded like any number: the stage must be in a fragment it cited.
# ---------------------------------------------------------------------------

STAGE_CLAIMS <- c(
  heart_failure = "nyha\\W{0,12}(?:classe|stade)?\\W{0,3}(iv|iii|3|4)\\b|(?:classe|stade)\\W{0,3}(iv|iii|3|4)\\W{0,8}(?:de la |de )?nyha",
  copd = "\\bgold\\W{0,6}(3|4|iii|iv)\\b"
)

facts_stage_claims <- function(run, stay, producer) {
  cr <- run$criteria[run$criteria$EVTID == stay$EVTID & endsWith(run$criteria$criterion, "aggression"), , drop = FALSE]
  parts <- list()
  for (i in seq_len(nrow(cr))) {
    why <- fold(cr$rationale[[i]])
    quotes <- fold(cr$evidence[[i]]$quote %||% character())
    for (concept in names(STAGE_CLAIMS)) {
      if (!grepl(STAGE_CLAIMS[[concept]], why, perl = TRUE)) next
      stage <- regmatches(why, regexpr(STAGE_CLAIMS[[concept]], why, perl = TRUE))
      token <- if (concept == "heart_failure") "nyha" else "gold"
      ok <- any(grepl(STAGE_CLAIMS[[concept]], quotes, perl = TRUE))
      id <- new_ids(1L)
      parts[[length(parts) + 1L]] <- list(
        facts = facts_frame(
          fact_id = id, PATID = stay$PATID, EVTID = stay$EVTID, concept = concept,
          value_chr = stage,
          derivation = "stated", source = "doceds", producer = producer,
          producer_version = paste(unique(run$assessments$model)),
          status = if (ok) "kept" else "refused",
          reason = if (ok) NA else paste0("the stage is not in any fragment cited for it (", token,
            if (any(grepl(token, quotes))) " is cited without this stage)" else " is not cited at all)"),
          note = "stage named in the aggression rationale"
        ),
        evidence = cited(id, cr$evidence[[i]])
      )
    }
  }
  bind_parts(parts)
}

# ---------------------------------------------------------------------------
# Derived facts. Gap 2: a computed value is a fact whose evidence is the facts
# it was computed from. Who owns its provenance: the rule that computed it,
# named and versioned in `producer`.
# ---------------------------------------------------------------------------

# A loss written in kilograms floors the percentage once divided by an upper
# bound on the weight it was lost from: a reference weight, or a weight
# measured during the stay plus the loss itself. `.denut_reference_ceiling()`,
# transcribed. With no weight at all, the derivation is refused, not guessed.
derive_kg_floors <- function(facts, stay) {
  kept <- facts[facts$EVTID == stay$EVTID & facts$status == "kept", , drop = FALSE]
  kg <- kept[kept$concept == "weight_loss" & kept$unit %in% "kg" & !kept$negated, , drop = FALSE]
  if (!nrow(kg)) return(bind_parts(list()))
  w <- kept[kept$concept == "weight", , drop = FALSE]
  refs <- w[w$reference %in% c("earlier", "usual", "before_disease"), , drop = FALSE]
  current <- w[w$reference %in% "current", , drop = FALSE]
  parts <- lapply(seq_len(nrow(kg)), function(i) {
    lost <- kg$value[[i]]
    bounds <- c(refs$value, current$value + lost)
    from <- c(refs$fact_id, current$fact_id)
    id <- new_ids(1L)
    if (!length(bounds)) {
      return(list(
        facts = facts_frame(fact_id = id, PATID = stay$PATID, EVTID = stay$EVTID,
          concept = "weight_loss", unit = "%", bound = "lower", reference = kg$reference[[i]],
          span_lo = kg$span_lo[[i]], span_hi = kg$span_hi[[i]], derivation = "derived",
          source = "facts", producer = "rule:kg_to_percent", producer_version = "proto-1",
          status = "refused", reason = "no documented weight to divide the loss by"),
        evidence = parents(id, kg$fact_id[[i]])
      ))
    }
    j <- which.max(bounds)
    list(
      facts = facts_frame(fact_id = id, PATID = stay$PATID, EVTID = stay$EVTID,
        concept = "weight_loss", value = lost / bounds[[j]] * 100, unit = "%", bound = "lower",
        reference = kg$reference[[i]], span_lo = kg$span_lo[[i]], span_hi = kg$span_hi[[i]],
        derivation = "derived", source = "facts", producer = "rule:kg_to_percent",
        producer_version = "proto-1",
        note = sprintf("%g kg / %g kg = at least %.1f %%", lost, bounds[[j]], lost / bounds[[j]] * 100)),
      evidence = parents(id, c(kg$fact_id[[i]], from[[j]]))
    )
  })
  bind_parts(parts)
}
