# PROTOTYPE -- throwaway. Builds the facts for the 64 test stays, evaluates the
# grid twice -- aggression as the model judged it, and aggression from facts --
# compares with the luna run the facts came from, and writes everything outside
# this tree.
#
# summary.log holds aggregates only: no identifier, no text, stays numbered
# 1-64. report.txt holds quotes and identifiers, for a reader on this machine.

loc <- Sys.setlocale("LC_ALL", "English_United States.utf8")
options(warn = 1)
here <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))))
src <- Sys.getenv("REDSANCODING_SRC")
od <- "C:/Users/franc/AppData/Roaming/R/data/R/redsancoding/denut"
datasets <- "C:/Users/franc/Documents/Datasets/denut"
out_dir <- file.path(tools::R_user_dir("extractionengine", "data"), "fact-layer-prototype")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# The catalog records the trimmer's identity for audit only, and no trimmer
# artifact is installed on this machine; the fragments do not depend on it.
assignInNamespace("doceds_onnx_spec", function(model_dir = NULL) list(package = "redsan", digest = NA_character_), ns = "redsan")
pkgload::load_all(src, export_all = TRUE, helpers = FALSE, quiet = TRUE)
for (f in c("facts.R", "rules.R", "grid.R")) source(file.path(here, f))

source(file.path(od, "aggression-b1-batch-ids-20261001.R"))
corpus <- readRDS(file.path(datasets, "denut_trimmed_v1.2.0_fiche_cora_2026-09-23.rds"))
bundles <- corpus[batch_ids]
# Gap 1 over the whole corpus: which analyte codes does the label predicate
# select, and would a code list have done?
lab <- do.call(rbind, lapply(corpus, function(b) {
  x <- b$sources$biol
  x <- x[!is.na(x$TYPEANA_LABEL) & grepl(ALBUMIN_LABEL, x$TYPEANA_LABEL, ignore.case = TRUE) &
    !grepl(ALBUMIN_EXCLUDE, x$TYPEANA_LABEL, ignore.case = TRUE, perl = TRUE), c("EVTID", "TYPEANA", "UNITE")]
  x
}))
albumin_codes <- vapply(split(lab$EVTID, paste(lab$TYPEANA, ifelse(grepl("^g\\s*/\\s*l$", lab$UNITE, ignore.case = TRUE), "g/L", "other unit"))),
  function(e) sprintf("%d rows in %d stays", length(e), length(unique(e))), "")
rm(corpus)
invisible(gc())
luna <- readRDS(file.path(od, "gpt6-low-779-v120-fiche-cora-aggression-crp-20260929-r2.rds"))
bonsai <- readRDS(file.path(od, "bonsai2-27b-budget2048-64-v120-fiche-cora-aggression-catabolism-20261002-s1.rds"))
review <- readxl::read_excel(file.path(datasets, "denut-revue-codage-2026-09-12.xlsx"), sheet = 1)

log <- character()
say <- function(...) log <<- c(log, paste0(...))
git <- function(...) system2("git", c("-C", shQuote(here), ...), stdout = TRUE)
say("RUN ", format(Sys.time(), "%Y-%m-%d %H:%M"), " | prototype commit ", substr(git("rev-parse", "HEAD"), 1, 7),
  " | tree clean ", !length(git("status", "--porcelain", "--", "."))," | luna run ",
  unique(luna$assessments$run_label), " | redsancoding source ", basename(src))
tab <- function(x) {
  t <- table(x, useNA = "ifany")
  paste(sprintf("%s=%d", names(t), as.integer(t)), collapse = ", ")
}
same <- function(a, b) mapply(identical, a, b)
group_of <- setNames(rep(names(batch), lengths(batch)), unlist(batch))
n_of <- setNames(seq_along(batch_ids), batch_ids)

# --- facts -------------------------------------------------------------------

stays <- do.call(rbind, lapply(bundles, stay_of))
DEMO <- c("luna-r2-rationale", "bonsai-rationale")
parts <- list()
for (id in batch_ids) {
  b <- bundles[[id]]
  stay <- stays[stays$EVTID == id, ]
  input <- .denut_model_input(b)
  docs_type <- setNames(
    vapply(input$documents, function(r) b$sources$doceds$RECTYPE[[r$source_row]], ""),
    vapply(input$documents, `[[`, "", "prompt_record_id")
  )
  parts <- c(parts, list(
    facts_biology(b, stay), facts_pmsi(b, stay),
    facts_luna(luna, stay, input$index, "luna-r2"),
    facts_lexicon(stay, input$index, docs_type),
    facts_stage_claims(luna, stay, DEMO[[1L]]), facts_stage_claims(bonsai, stay, DEMO[[2L]])
  ))
}
built <- bind_parts(parts)
derived <- bind_parts(lapply(batch_ids, function(id) derive_kg_floors(built$facts, stays[stays$EVTID == id, ])))
facts <- rbind(built$facts, derived$facts)
evidence <- rbind(built$evidence, derived$evidence)
stopifnot(!anyDuplicated(facts$fact_id), all(evidence$fact_id %in% facts$fact_id))

say("FACTS: ", nrow(facts), " over ", length(unique(facts$EVTID)), " stays | evidence rows ", nrow(evidence))
say("  by producer x status: ", tab(paste(facts$producer, facts$status)))
say("  by concept (kept): ", tab(facts$concept[facts$status == "kept" & !startsWith(facts$concept, "judgement:")]))
say("  judgement facts: ", tab(paste(sub("judgement:", "", facts$concept[startsWith(facts$concept, "judgement:")]),
  facts$value_chr[startsWith(facts$concept, "judgement:")])))
say("  derivation (kept): ", tab(facts$derivation[facts$status == "kept"]))
say("  qualifiers on lexicon facts: negated ", sum(facts$negated[facts$producer == "lexicon"]),
  ", hypothetical ", sum(facts$hypothetical[facts$producer == "lexicon"]),
  ", historical ", sum(facts$historical[facts$producer == "lexicon"]),
  ", family ", sum(facts$family[facts$producer == "lexicon"]), " of ", sum(facts$producer == "lexicon"))
say("  refusal reasons: ", tab(gsub("[0-9]+([.,][0-9]+)?", "#", facts$reason[facts$status == "refused"])))
wl <- facts[facts$concept == "weight_loss" & facts$status == "kept" & !facts$negated, ]
say("  weight_loss time model (kept): ", tab(paste(wl$reference, wl$unit, wl$bound,
  ifelse(is.na(wl$span_lo), "", paste0("[", wl$span_lo, ",", wl$span_hi, "]")))))

# Lineage: every fact a decision can rest on resolves, through derived facts,
# to a quote or a source row.
grounds <- function(id, seen = character()) {
  if (id %in% seen) return(FALSE)
  e <- evidence[evidence$fact_id == id, ]
  if (!nrow(e)) return(FALSE)
  direct <- any(e$kind %in% c("fragment", "source_row") & !is.na(e$quote))
  up <- e$parent_fact_id[e$kind == "fact"]
  direct || (length(up) && all(vapply(up, grounds, NA, seen = c(seen, id))))
}

# --- the grid, twice ----------------------------------------------------------

kept <- facts[facts$status == "kept" & !facts$producer %in% DEMO, ]
run_grid <- function(grid, variant) {
  crit <- list()
  verd <- list()
  for (id in batch_ids) {
    c1 <- evaluate_band(grid, stays[stays$EVTID == id, ], kept[kept$EVTID == id, ])
    crit[[id]] <- cbind(variant = variant, c1, stringsAsFactors = FALSE)
    verd[[id]] <- cbind(variant = variant, verdict(c1), stringsAsFactors = FALSE)
  }
  list(criteria = do.call(rbind, crit), verdicts = do.call(rbind, verd))
}
A <- run_grid(has_grid(), "judged")
B <- run_grid(has_grid(aggression = aggression_from_facts), "facts")

decided <- A$criteria[A$criteria$state != "unknown", ]
used <- unique(unlist(strsplit(decided$facts[nzchar(decided$facts)], ",")))
say("")
say("LINEAGE: decided criteria ", nrow(decided), " | with no fact ", sum(!nzchar(decided$facts)),
  " | facts used ", length(used), " | of which resolve to a quote or a source row ",
  sum(vapply(used, grounds, NA)))
say("  decided criteria resting on a derived fact: ",
  sum(vapply(strsplit(decided$facts, ","), function(x) any(facts$derivation[match(x, facts$fact_id)] == "derived"), NA)))

# --- A against luna -----------------------------------------------------------

lc <- luna$criteria[luna$criteria$EVTID %in% batch_ids, c("EVTID", "criterion", "assessment")]
m <- merge(A$criteria, lc, by = c("EVTID", "criterion"), all = TRUE)
say("")
say("GRID (aggression judged) AGAINST LUNA, same facts")
say("  criteria compared ", nrow(m), " | absent on one side ", sum(is.na(m$state) | is.na(m$assessment)),
  " | equal ", sum(m$state == m$assessment, na.rm = TRUE))
dif <- m[!is.na(m$state) & !is.na(m$assessment) & m$state != m$assessment, ]
if (nrow(dif)) say("  differences: ", tab(paste(sub("^[^.]+[.]", "", dif$criterion), dif$assessment, "->", dif$state)))
la <- luna$assessments[match(batch_ids, luna$assessments$EVTID), ]
va <- A$verdicts[match(batch_ids, A$verdicts$EVTID), ]
say("  band equal ", sum(same(la$band, vapply(batch_ids, function(id) A$criteria$band[A$criteria$EVTID == id][[1L]], ""))), " of 64")
for (k in c("phenotypic", "etiologic", "diagnosis", "severity")) {
  say(sprintf("  %-20s equal %d of 64", k, sum(same(va[[k]], la[[k]]))))
}
canon <- function(x) vapply(strsplit(ifelse(is.na(x), "", x), ", "), function(s) paste(sort(s), collapse = ","), "")
say(sprintf("  %-20s equal %d of 64", "severity_unresolved", sum(canon(va$severity_unresolved) == canon(la$severity_unresolved))))
if (nrow(dif)) {
  say("  per difference (stay number, criterion, luna -> grid, facts behind the grid answer):")
  for (i in seq_len(nrow(dif))) {
    ids <- strsplit(dif$facts[[i]], ",")[[1L]]
    f <- facts[match(ids, facts$fact_id), ]
    say(sprintf("    #%d %s %s -> %s | %s", n_of[[dif$EVTID[[i]]]], sub("^[^.]+[.]", "", dif$criterion[[i]]),
      dif$assessment[[i]], dif$state[[i]],
      paste(sprintf("%s %s %s %s %s [%s,%s]", f$concept, f$derivation, f$unit, f$bound, f$reference,
        f$span_lo, f$span_hi), collapse = "; ")))
  }
}

# --- B: aggression from facts --------------------------------------------------

agg_of <- function(x, ids) {
  r <- x$criteria[x$criteria$EVTID %in% ids & endsWith(x$criteria$criterion, "aggression"), ]
  r$assessment[match(ids, r$EVTID)]
}
branch <- vapply(batch_ids, function(id) {
  ctx <- list(stay = stays[stays$EVTID == id, ], facts = kept[kept$EVTID == id, ], path = "etiologic.aggression")
  hits <- vapply(aggression_branches, function(b) evaluate(b, ctx)$state, "")
  if (any(hits == "met")) paste(names(hits)[hits == "met"], collapse = "+") else "none"
}, "")
box <- vapply(batch_ids, function(id) any(kept$EVTID == id & kept$concept == "box:aggression"), NA)
agg <- data.frame(
  EVTID = batch_ids, n = seq_along(batch_ids), group = group_of[batch_ids],
  luna = agg_of(luna, batch_ids), bonsai = agg_of(bonsai, batch_ids),
  facts = B$criteria$state[match(paste0(batch_ids, "etiologic.aggression"),
    paste0(B$criteria$EVTID, sub("^[^.]+[.]", "", B$criteria$criterion)))],
  branch = branch, box = box, stringsAsFactors = FALSE
)
say("")
say("AGGRESSION FROM FACTS (deterministic producers only)")
for (g in names(batch)) {
  s <- agg[agg$group == g, ]
  say(sprintf("  %-16s n=%2d | luna: %s | bonsai: %s | facts: %s | branches: %s | dietitian box ticked: %d",
    g, nrow(s), tab(s$luna), tab(s$bonsai), tab(s$facts), tab(s$branch[s$branch != "none"]), sum(s$box)))
}
src_of <- function(concepts) {
  x <- kept[kept$concept %in% concepts, ]
  tab(paste(x$concept, x$source))
}
say("  closed-list facts by concept and source: ", src_of(c(names(ICD10_SETS), "major_surgery", names(LEXICON))))
say("  albumin facts by analyte code: ", tab(paste(facts$value_chr, facts$status)[facts$concept == "albumin"]))
say("  albumin label predicate over all 779 stays, by code and unit: ",
  paste(names(albumin_codes), albumin_codes, sep = ": ", collapse = " | "))
say("  box ticked and facts met: ", sum(agg$box & agg$facts == "met"), " | box ticked and facts unknown: ",
  sum(agg$box & agg$facts != "met"), " | box absent and facts met: ", sum(!agg$box & agg$facts == "met"))

vb <- B$verdicts[match(batch_ids, B$verdicts$EVTID), ]
say("  diagnosis judged -> facts: ", tab(paste(va$diagnosis, "->", vb$diagnosis)))
say("  bonsai (final text) against facts: ", tab(paste(agg$bonsai, "|", agg$facts)))
say("  computed and structured criteria equal to luna: ",
  sum(m$state == m$assessment & !sub("^[^.]+[.]", "", m$criterion) %in% NARRATIVE), " of ",
  sum(!sub("^[^.]+[.]", "", m$criterion) %in% NARRATIVE))

# --- Francesco's review: only `decision` is his judgement ---------------------

rv <- review[as.character(review$EVTID) %in% batch_ids, ]
dec <- vapply(batch_ids, function(id) paste(sort(unique(rv$decision[as.character(rv$EVTID) == id])), collapse = "+"), "")
say("")
say("REVIEW DECISION (Francesco, 2026-09-12) against the grid, per stay")
say("  decisions: ", tab(dec))
say("  judged aggression: ", tab(paste(dec, "|", va$diagnosis)))
say("  aggression from facts: ", tab(paste(dec, "|", vb$diagnosis)))

# --- an invented stage --------------------------------------------------------

st <- facts[facts$producer %in% DEMO, ]
say("")
say("STAGES NAMED IN AGGRESSION RATIONALES, read as facts and grounded")
say("  ", if (nrow(st)) tab(paste(st$producer, st$concept, st$value_chr, st$status)) else "none")
if (any(st$status == "refused")) say("  reasons: ", tab(st$reason[st$status == "refused"]))
nyha_text <- vapply(batch_ids, function(id) {
  any(kept$EVTID == id & kept$concept == "nyha_class" & kept$producer == "lexicon")
}, NA)
say("  stays whose documents state a NYHA class (lexicon): ", sum(nyha_text),
  " | stays with a refused stage claim among them: ", sum(nyha_text[unique(st$EVTID[st$status == "refused"])]))
for (id in unique(st$EVTID)) {
  s <- agg[agg$EVTID == id, ]
  say(sprintf("  stay #%d (%s): bonsai aggression %s | from facts %s (%s) | luna %s",
    s$n, s$group, s$bonsai, s$facts, s$branch, s$luna))
}

# --- silence ------------------------------------------------------------------

surface <- vapply(batch_ids, function(id) {
  ix <- .denut_model_input(bundles[[id]])$index
  any(grepl("(poids|pese|imc|bmi)\\W{0,25}[0-9]", fold(ix$quote[startsWith(ix$prompt_record_id, "DOC-")]), perl = TRUE))
}, NA)
anthropometry <- vapply(batch_ids, function(id) {
  any(kept$EVTID == id & kept$producer == "luna-r2" & kept$concept %in% c("bmi", "weight", "weight_loss"))
}, NA)
say("")
say("SILENCE PROBES")
say("  stays whose visible text writes a weight or BMI with a number: ", sum(surface),
  " | of which no weight, BMI or loss fact from the model: ", sum(surface & !anthropometry))
tb <- vapply(batch_ids, function(id) any(kept$EVTID == id & kept$concept == "antituberculous_drug"), NA)
tb_why <- vapply(batch_ids, function(id) {
  r <- luna$criteria[luna$criteria$EVTID == id & endsWith(luna$criteria$criterion, "aggression"), ]
  grepl("tubercul|bcg|mycobact", fold(r$rationale[[1L]]))
}, NA)
say("  stays with an anti-tuberculous drug fact: ", sum(tb), " | luna's aggression rationale names the mycobacterial infection in ",
  sum(tb & tb_why), " of them")
for (id in batch_ids[tb]) {
  s <- agg[agg$EVTID == id, ]
  d <- kept[kept$EVTID == id & kept$concept == "antituberculous_drug", ]
  say(sprintf("  stay #%d (%s): %d drug facts (%s) | historical %d, negated %d | from facts %s (%s) | luna names it %s | bonsai %s",
    s$n, s$group, nrow(d), paste(sort(unique(d$value_chr)), collapse = "+"), sum(d$historical), sum(d$negated),
    s$facts, s$branch, tb_why[[id]], s$bonsai))
}

# The child band never runs on this batch. Synthetic facts, no patient: does it
# evaluate, and do the IOTF curves bite?
child <- data.frame(EVTID = "synthetic", PATID = "synthetic", age = 10, sex = "M",
  admission = Sys.Date(), discharge = Sys.Date(), stringsAsFactors = FALSE)
for (b in c(13, 15, 17)) {
  f <- facts_frame(fact_id = c("S1", "S2"), PATID = "synthetic", EVTID = "synthetic",
    concept = c("bmi", "weight_loss"), value = c(b, 6), unit = c("kg/m2", "%"),
    reference = c("current", "timed"), span_lo = c(NA, 28), span_hi = c(NA, 31), derivation = "stated")
  ch <- evaluate_band(has_grid(), child, f)
  say(sprintf("  synthetic child, 10 y, male, BMI %g, -6 %% in a month: %s | verdict %s", b,
    paste(sub("^child[.]", "", ch$criterion[ch$state != "unknown"]), ch$state[ch$state != "unknown"], collapse = ", "),
    paste(unlist(verdict(ch)[c("diagnosis", "severity")]), collapse = "/")))
}

# --- the page -----------------------------------------------------------------

code_lines <- function(path) {
  x <- trimws(readLines(path, warn = FALSE))
  sum(nzchar(x) & !startsWith(x, "#"))
}
say("")
say("SIZE (non-blank, non-comment lines): grid.R ", code_lines(file.path(here, "grid.R")),
  " | rules.R ", code_lines(file.path(here, "rules.R")), " | facts.R ", code_lines(file.path(here, "facts.R")))

# --- outputs ------------------------------------------------------------------

saveRDS(list(stays = stays, facts = facts, evidence = evidence, judged = A, from_facts = B,
  aggression = agg, review_decision = dec, luna_vs_grid = m), file.path(out_dir, "fact-layer-64.rds"))
writeLines(iconv(log, "UTF-8", "ASCII//TRANSLIT"), file.path(out_dir, "summary.log"))

# A report for a reader on this machine: identifiers and quotes.
clip <- function(x, n = 180) ifelse(nchar(x) > n, paste0(substr(x, 1, n), "..."), x)
explain <- function(id, indent = "      ", depth = 0L) {
  f <- facts[facts$fact_id == id, ]
  head <- sprintf("%s%s %s %s%s%s %s%s%s [%s %s]", indent, id, f$concept,
    ifelse(is.na(f$value), "", format(round(f$value, 2))), ifelse(is.na(f$unit), "", paste0(" ", f$unit)),
    ifelse(is.na(f$value_chr), "", paste0(" ", f$value_chr)),
    ifelse(is.na(f$reference), "", f$reference),
    ifelse(is.na(f$span_lo), "", sprintf(" %g-%g d", f$span_lo, f$span_hi)),
    ifelse(f$bound == "lower", " (floor)", ""), f$producer, f$status)
  e <- evidence[evidence$fact_id == id, ]
  lines <- c(head, if (!is.na(f$note) && depth == 0L) paste0(indent, "  note: ", clip(f$note, 240)))
  for (i in seq_len(nrow(e))) {
    lines <- c(lines, if (e$kind[[i]] == "fact") {
      if (depth < 3L) explain(e$parent_fact_id[[i]], paste0(indent, "  <- "), depth + 1L)
    } else {
      sprintf("%s  [%s] \"%s\"", indent, ifelse(is.na(e$fragment_id[[i]]), e$record_ref[[i]], e$fragment_id[[i]]),
        clip(e$quote[[i]]))
    })
  }
  lines
}
report <- character()
for (id in batch_ids) {
  a <- agg[agg$EVTID == id, ]
  s <- stays[stays$EVTID == id, ]
  report <- c(report, "", strrep("=", 78),
    sprintf("#%d  %s  %s  age %g  %s", n_of[[id]], id, a$group, s$age, A$criteria$band[A$criteria$EVTID == id][[1L]]),
    sprintf("review decision: %s", dec[[id]]),
    sprintf("luna:            %s / %s", la$diagnosis[la$EVTID == id], la$severity[la$EVTID == id]),
    sprintf("grid, judged:    %s / %s", va$diagnosis[va$EVTID == id], va$severity[va$EVTID == id]),
    sprintf("grid, facts:     %s / %s   aggression from facts: %s (%s); dietitian box: %s; bonsai: %s",
      vb$diagnosis[vb$EVTID == id], vb$severity[vb$EVTID == id], a$facts, a$branch,
      if (a$box) "ticked" else "-", a$bonsai))
  cr <- A$criteria[A$criteria$EVTID == id, ]
  for (i in seq_len(nrow(cr))) {
    report <- c(report, sprintf("  %-22s %s", sub("^[^.]+[.]", "", cr$criterion[[i]]), cr$state[[i]]))
    if (cr$state[[i]] != "unknown" || nzchar(cr$facts[[i]])) {
      for (fid in strsplit(cr$facts[[i]], ",")[[1L]]) report <- c(report, explain(fid))
    }
  }
  closed <- kept[kept$EVTID == id & kept$concept %in% c(names(ICD10_SETS), "major_surgery", names(LEXICON), "box:aggression"), ]
  if (nrow(closed)) {
    report <- c(report, "  closed-list and box facts:")
    for (fid in closed$fact_id) report <- c(report, explain(fid))
  }
  refused <- facts[facts$EVTID == id & facts$status == "refused", ]
  if (nrow(refused)) {
    report <- c(report, "  refused facts:")
    for (i in seq_len(nrow(refused))) {
      report <- c(report, sprintf("      %s %s (%s): %s", refused$fact_id[[i]], refused$concept[[i]],
        refused$producer[[i]], refused$reason[[i]]))
    }
  }
}
writeLines(iconv(report, "UTF-8", "ASCII//TRANSLIT"), file.path(out_dir, "report.txt"))
writeLines(c("done", out_dir))
