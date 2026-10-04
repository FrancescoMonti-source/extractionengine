# PROTOTYPE -- throwaway. The real test: the grid over facts the local model
# extracted from scratch (extract_every_fact.R), against DENUT + Bonsai's two
# runs, luna r2 and Francesco's decision column, read as NOTE.md fixed it
# before the run.
#
#   Rscript compare.R       # seed 1: compare.log, compare-report.txt, compare-64.rds
#   Rscript compare.R 2     # seed 2: compare-s2.*, and seed 2 against seed 1
#
# compare.log holds aggregates only: no identifier, no text, stays numbered
# 1-64. compare-report.txt holds quotes and identifiers, for a reader on this
# machine.

loc <- Sys.setlocale("LC_ALL", "English_United States.utf8")
options(warn = 1)
seed <- as.integer(c(commandArgs(trailingOnly = TRUE), "1")[1])
stopifnot(!is.na(seed), seed >= 1L)
sfx <- if (seed != 1L) paste0("-s", seed) else ""
here <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))))
src <- Sys.getenv("REDSANCODING_SRC")
od <- "C:/Users/franc/AppData/Roaming/R/data/R/redsancoding/denut"
datasets <- "C:/Users/franc/Documents/Datasets/denut"
out_dir <- file.path(tools::R_user_dir("extractionengine", "data"), "fact-layer-prototype")

assignInNamespace("doceds_onnx_spec", function(model_dir = NULL) list(package = "redsan", digest = NA_character_), ns = "redsan")
pkgload::load_all(src, export_all = TRUE, helpers = FALSE, quiet = TRUE)
for (f in c("facts.R", "rules.R", "grid.R", "atomic.R", "every_fact.R")) source(file.path(here, f))
source(file.path(od, "aggression-b1-batch-ids-20261001.R"))
corpus <- readRDS(file.path(datasets, "denut_trimmed_v1.2.0_fiche_cora_2026-09-23.rds"))
bundles <- corpus[batch_ids]
rm(corpus)
invisible(gc())
rd <- function(f) readRDS(file.path(od, f))
luna <- rd("gpt6-low-779-v120-fiche-cora-aggression-crp-20260929-r2.rds")
cat64 <- rd("bonsai2-27b-budget2048-64-v120-fiche-cora-aggression-catabolism-20261002-s1.rds")
c23 <- rd("bonsai2-27b-budget2048-23-v120-fiche-cora-aggression-closed-20261001-s1.rds")
c41 <- rd("bonsai2-27b-budget2048-41-v120-fiche-cora-aggression-closed-20261002-s1.rds")
review <- readxl::read_excel(file.path(datasets, "denut-revue-codage-2026-09-12.xlsx"), sheet = 1)
ck <- readRDS(file.path(out_dir, paste0("every-fact-bonsai-64", sfx, ".rds")))

log <- character()
say <- function(...) log <<- c(log, paste0(...))
git <- function(...) system2("git", c("-C", shQuote(here), ...), stdout = TRUE)
tab <- function(x) {
  t <- table(x, useNA = "ifany")
  paste(sprintf("%s=%d", names(t), as.integer(t)), collapse = ", ")
}
ords <- function(i) if (length(i)) paste0("#", i, collapse = ",") else "none"
group_of <- setNames(rep(names(batch), lengths(batch)), unlist(batch))
rv <- review[as.character(review$EVTID) %in% batch_ids, ]
dec <- vapply(batch_ids, function(id) paste(sort(unique(rv$decision[as.character(rv$EVTID) == id])), collapse = "+"), "")
KINDS <- c("weights", "heights", "bmis", "losses", "stable_weight", "intake", "feeding", "absorption", "muscle", "conditions")
PRODUCER <- "bonsai-every-fact"
RULES <- c("rule:bmi", "rule:weight_change", "rule:kg_to_percent", "rule:duration_days")

commit <- git("rev-parse", "HEAD")
say("RUN ", format(Sys.time(), "%Y-%m-%d %H:%M"), " | seed ", seed, " | prototype commit ", substr(commit, 1, 7),
  " | tree clean ", !length(git("status", "--porcelain", "--", ".")), " | redsancoding source ", basename(src))
say("MODEL ", ck$identity$model, " | question ", substr(ck$identity$question_digest, 1, 8),
  " | chat ", substr(ck$identity$chat_digest, 1, 8), " | build ", ck$identity$build)

# --- facts ---------------------------------------------------------------------

status_of <- vapply(batch_ids, function(id) {
  s <- ck$stays[[id]]
  if (is.null(s)) "not run" else if (is.null(s$response)) "failed" else
    if (!sum(lengths(s$response[KINDS]))) "empty" else "answered"
}, "")
stays <- do.call(rbind, lapply(bundles, stay_of))
version <- paste(ck$identity$model, substr(ck$identity$question_digest, 1, 8))
parts <- list()
shown <- list()
for (id in batch_ids) {
  stay <- stays[stays$EVTID == id, ]
  parts <- c(parts, list(facts_biology(bundles[[id]], stay)))
  ix <- .denut_model_input(bundles[[id]])$index
  ix <- ix[startsWith(ix$prompt_record_id, "DOC-"), , drop = FALSE]
  shown[[id]] <- ix
  if (status_of[[id]] == "answered") {
    parts <- c(parts, list(facts_every(ck$stays[[id]]$response, stay, ix, PRODUCER, version)))
  }
}
built <- bind_parts(parts)
d1 <- bind_parts(lapply(batch_ids, function(id) derive_from_weights(built$facts, stays[stays$EVTID == id, ])))
f1 <- rbind(built$facts, d1$facts)
d2 <- bind_parts(lapply(batch_ids, function(id) derive_kg_floors(f1, stays[stays$EVTID == id, ])))
facts <- rbind(f1, d2$facts)
evidence <- rbind(built$evidence, d1$evidence, d2$evidence)
stopifnot(!anyDuplicated(facts$fact_id), all(evidence$fact_id %in% facts$fact_id))
kept <- facts[facts$status == "kept", ]

secs <- vapply(ck$stays, `[[`, 1, "seconds")
mf <- facts[facts$producer == PRODUCER, ]
say("")
say("EXTRACTION")
say("  stays: ", tab(status_of), " | failed or empty: ", ords(which(status_of != "answered")),
  " | seconds median ", round(median(secs)), ", total h ", round(sum(secs) / 3600, 2))
# The error class only: a parse error's message can quote what the model wrote.
fails <- vapply(ck$stays, function(s) if (is.null(s$response)) s$error else NA_character_, "")
if (any(!is.na(fails))) say("  failure classes: ", tab(fails[!is.na(fails)]))
items <- sapply(KINDS, function(k) vapply(batch_ids, function(id) length(ck$stays[[id]]$response[[k]]), 1L))
say("  items returned, total by kind: ", paste(KINDS, colSums(items), sep = "=", collapse = ", "))
say("  model facts ", nrow(mf), " | kept ", sum(mf$status == "kept"), " | refused ", sum(mf$status == "refused"))
say("  refusal reasons: ", tab(mf$reason[mf$status == "refused"]))
say("  refused by concept: ", tab(sub(":.*", "", mf$concept[mf$status == "refused"])))
# A number refused for its citation: is it written in another fragment of the
# stay (the model pointed at the wrong line) or in none (it is not in the
# record)? And when elsewhere, how far from the fragment it cited: the next
# fragment of the same document would point at the cutting, not the model.
num <- mf[mf$status == "refused" & grepl("does not appear in any fragment cited", mf$reason) & !is.na(mf$value), ]
elsewhere <- vapply(seq_len(nrow(num)), function(i) {
  ix <- shown[[num$EVTID[[i]]]]
  hit <- which(vapply(ix$quote, function(x) grounded(num$value[[i]], x, height = num$concept[[i]] == "height"), NA))
  if (!length(hit)) return("written nowhere in the stay")
  at <- match(evidence$fragment_id[evidence$fact_id == num$fact_id[[i]]], ix$evidence_id)
  at <- at[!is.na(at)]
  d <- abs(outer(at, hit, `-`))
  d[!outer(ix$prompt_record_id[at], ix$prompt_record_id[hit], `==`)] <- Inf
  d <- min(d)
  if (is.infinite(d)) "in another document" else if (d == 1) "in the next fragment" else
    if (d <= 3) "2-3 fragments away" else "further in the same document"
}, "")
say("  numbers refused for their citation, where the number is: ", tab(paste(num$concept, elsewhere)))
say("  derived facts: ", tab(paste(facts$producer, facts$status)[facts$producer %in% RULES]))
say("  derived refusals: ", tab(facts$reason[facts$producer %in% RULES & facts$status == "refused"]))
w <- mf[mf$concept == "weight", ]
say("  weights by reference and status: ", tab(paste(w$reference, w$status)))
say("  earlier weights kept with no date R can read: ", sum(w$reference %in% "earlier" & w$status == "kept" & is.na(w$span_lo)),
  " of ", sum(w$reference %in% "earlier" & w$status == "kept"))
l <- mf[mf$concept == "weight_loss" & !mf$negated, ]
say("  written losses by unit, reference and status: ", tab(paste(l$unit, l$reference, l$status)))
say("  written losses kept with no time or reference R can read: ", sum(l$status == "kept" & l$note %in% "no time or reference R can read"))
say("  stable-weight statements: ", tab(mf$status[mf$concept == "weight_loss" & mf$negated]))
it <- mf[mf$concept == "intake_reduction", ]
say("  intake: ", tab(paste(ifelse(it$negated, "preserved", "reduced"), it$status)),
  " | reduced and kept: amount read ", sum(!it$negated & it$status == "kept" & !is.na(it$value)),
  ", duration read ", sum(!it$negated & it$status == "kept" & !is.na(it$span_lo)), ", basis ",
  tab(it$value_chr[!it$negated & it$status == "kept"]))
say("  feeding: ", tab(paste(mf$concept, mf$status)[grepl("feeding", mf$concept)]),
  " | absorption: ", tab(paste(mf$concept, mf$status)[startsWith(mf$concept, "absorption:")]),
  " | muscle: ", tab(paste(mf$concept, mf$status)[startsWith(mf$concept, "muscle:")]))
cd <- mf[mf$concept %in% ATOMIC_CONCEPTS, ]
say("  conditions: ", nrow(cd), " | kept ", sum(cd$status == "kept"), " | dated by R ", sum(!is.na(cd$span_lo)),
  " | onset (kept, acute list) ", tab(cd$onset[cd$status == "kept" & cd$concept %in% ACUTE]))

# --- the grid ------------------------------------------------------------------

G <- has_grid(aggression = aggression_from_facts, intake = intake_from_facts,
  absorption = absorption_from_facts, muscle = muscle_from_facts)
failed_ids <- batch_ids[status_of != "answered"]
crit <- list()
verd <- list()
for (id in batch_ids) {
  c1 <- evaluate_band(G, stays[stays$EVTID == id, ], kept[kept$EVTID == id, ])
  v1 <- verdict(c1)
  # The contract: a stay whose producer failed is not evaluated.
  if (id %in% failed_ids) {
    c1$state <- "failed"
    v1[c("phenotypic", "etiologic", "diagnosis")] <- "failed"
    v1[c("severity", "severity_unresolved")] <- NA_character_
  }
  crit[[id]] <- c1
  verd[[id]] <- v1
}
FC <- do.call(rbind, crit)
FV <- do.call(rbind, verd)

axis_of <- function(run, k) {
  a <- run$assessments
  i <- match(batch_ids, a$EVTID)
  ifelse(is.na(i), "absent", ifelse(!is.na(a$error_message[i]), "failed", ifelse(is.na(a[[k]][i]), "-", a[[k]][i])))
}
in23 <- batch_ids %in% c23$assessments$EVTID
closed_axis <- function(k) ifelse(in23, axis_of(c23, k), axis_of(c41, k))
fl_axis <- function(k) {
  x <- FV[[k]][match(batch_ids, FV$EVTID)]
  ifelse(is.na(x), "-", x)
}
crit_of <- function(run, name) {
  r <- run$criteria[endsWith(run$criteria$criterion, paste0(".", name)), ]
  x <- r$assessment[match(batch_ids, r$EVTID)]
  ifelse(is.na(x), "-", x)
}
closed_crit <- function(name) ifelse(in23, crit_of(c23, name), crit_of(c41, name))
fl_crit <- function(name) {
  r <- FC[endsWith(FC$criterion, paste0(".", name)), ]
  x <- r$state[match(batch_ids, r$EVTID)]
  ifelse(is.na(x), "-", x)
}

# --- the reading fixed before the run --------------------------------------------

ph <- list(fl = fl_axis("phenotypic"), cat64 = axis_of(cat64, "phenotypic"), closed = closed_axis("phenotypic"),
  luna = axis_of(luna, "phenotypic"))
set44 <- dec == "Justifiable" & ph$luna == "met"
lost <- lapply(ph[c("fl", "cat64", "closed")], function(x) which(set44 & x != "met"))
n_fl <- length(lost$fl)
say("")
say("THE READING (NOTE.md, written before the run)")
say("  stays judged justifiable where luna established the phenotype: ", sum(set44))
say("  left without the phenotype: fact layer ", n_fl, " (", ords(lost$fl), ") | DENUT catabolism run ",
  length(lost$cat64), " (", ords(lost$cat64), ") | DENUT closed-list run ", length(lost$closed), " (", ords(lost$closed), ")")
say("  how the fact layer lost them: ", tab(ph$fl[lost$fl]))
say("  READING: ", if (n_fl <= 1) "clearly better (0 or 1)" else if (n_fl >= 11) "worse (11 or more)" else "about equal (2 to 10)")
nine <- c(16L, 23L, 28L, 36L, 44L, 51L, 57L, 61L, 63L)
say("  the 9 stays of the given prediction: fact layer ", tab(ph$fl[nine]), " | catabolism run ", tab(ph$cat64[nine]),
  " | closed run ", tab(ph$closed[nine]), " | phenotype established by the fact layer on ", ords(nine[ph$fl[nine] == "met"]))

# --- beside it, no threshold ------------------------------------------------------

answered <- function(x) !x %in% c("failed", "absent")
differ <- function(a, b) {
  both <- answered(a) & answered(b)
  sprintf("%2d of %2d", sum(a[both] != b[both]), sum(both))
}
say("")
say("AXES, stays answered by both, differing (catabolism vs closed is DENUT against itself: the noise)")
for (k in c("phenotypic", "etiologic", "diagnosis", "severity")) {
  fl <- fl_axis(k)
  ca <- axis_of(cat64, k)
  cl <- closed_axis(k)
  lu <- axis_of(luna, k)
  say(sprintf("  %-10s FL-catabolism %s | FL-closed %s | catabolism-closed %s | FL-luna %s | catabolism-luna %s | closed-luna %s",
    k, differ(fl, ca), differ(fl, cl), differ(ca, cl), differ(fl, lu), differ(ca, lu), differ(cl, lu)))
}
for (k in c("phenotypic", "diagnosis")) {
  say("  ", k, " by your decision, fact layer: ", tab(paste(dec, fl_axis(k))))
  say("  ", k, " by your decision, catabolism:  ", tab(paste(dec, axis_of(cat64, k))))
  say("  ", k, " by your decision, closed:      ", tab(paste(dec, closed_axis(k))))
  say("  ", k, " by your decision, luna:        ", tab(paste(dec, axis_of(luna, k))))
}
say("  phenotypic, luna -> fact layer: ", tab(paste(ph$luna, "->", ph$fl)))
say("  phenotypic, catabolism -> fact layer: ", tab(paste(ph$cat64, "->", ph$fl)))
gain <- which(ph$fl == "met" & ph$luna != "met")
say("  fact layer met where luna was not: ", ords(gain), " | your decision on them: ", tab(dec[gain]))
say("")
say("CRITERIA, luna -> fact layer (and catabolism -> fact layer)")
for (k in c("phenotypic.loss", "phenotypic.imc", "phenotypic.muscle", "etiologic.intake", "etiologic.absorption",
  "etiologic.aggression", "severe.albumin")) {
  say(sprintf("  %-22s luna->FL: %s", k, tab(paste(crit_of(luna, k), "->", fl_crit(k)))))
  say(sprintf("  %-22s catabolism->FL: %s", "", tab(paste(crit_of(cat64, k), "->", fl_crit(k)))))
}
say("")
say("THE STAYS THE FACT LAYER LOST, criteria and the anthropometric facts behind them")
ANTHRO <- c("weight", "height", "bmi", "weight_loss")
for (i in lost$fl) {
  id <- batch_ids[[i]]
  x <- facts[facts$EVTID == id & facts$concept %in% ANTHRO, ]
  say(sprintf("  #%d %s | %s | FL loss/imc/muscle %s/%s/%s | luna %s/%s/%s | catabolism %s | kept: %s | refused: %s", i, group_of[[id]],
    status_of[[id]], fl_crit("phenotypic.loss")[[i]], fl_crit("phenotypic.imc")[[i]], fl_crit("phenotypic.muscle")[[i]],
    crit_of(luna, "phenotypic.loss")[[i]], crit_of(luna, "phenotypic.imc")[[i]], crit_of(luna, "phenotypic.muscle")[[i]],
    ph$cat64[[i]],
    if (any(x$status == "kept")) tab(paste(x$concept, x$reference, x$derivation)[x$status == "kept"]) else "none",
    if (any(x$status == "refused")) tab(paste(x$concept, x$reason)[x$status == "refused"]) else "none"))
}

# --- outputs ------------------------------------------------------------------------

# --- this seed against seed 1 ----------------------------------------------------------
# The fact layer's own noise, beside DENUT's against itself (catabolism-closed
# above). Seed 1's verdicts must come from this same commit.

if (seed != 1L) {
  s1 <- readRDS(file.path(out_dir, "compare-64.rds"))
  if (!identical(s1$commit, commit)) stop("compare-64.rds is not from this commit: run compare.R for seed 1 first")
  s1_axis <- function(k) {
    x <- s1$verdicts[[k]][match(batch_ids, s1$verdicts$EVTID)]
    ifelse(is.na(x), "-", x)
  }
  s1_crit <- function(name) {
    r <- s1$criteria[endsWith(s1$criteria$criterion, paste0(".", name)), ]
    x <- r$state[match(batch_ids, r$EVTID)]
    ifelse(is.na(x), "-", x)
  }
  lost1 <- s1$lost$fl
  say("")
  say("SEED ", seed, " AGAINST SEED 1 (the fact layer against itself)")
  say("  of the ", sum(set44), " stays, left without the phenotype: seed 1 ", length(lost1), " (", ords(lost1), ") | seed ", seed, " ",
    n_fl, " (", ords(lost$fl), ") | by both: ", ords(intersect(lost1, lost$fl)))
  for (k in c("phenotypic", "etiologic", "diagnosis", "severity")) {
    say(sprintf("  %-10s differing, seed 1 vs seed %d: %s | catabolism-closed: %s", k, seed,
      differ(s1_axis(k), fl_axis(k)), differ(axis_of(cat64, k), closed_axis(k))))
  }
  say("  phenotypic, seed 1 -> seed ", seed, ": ", tab(paste(s1_axis("phenotypic"), "->", fl_axis("phenotypic"))))
  say("  diagnosis, seed 1 -> seed ", seed, ": ", tab(paste(s1_axis("diagnosis"), "->", fl_axis("diagnosis"))))
  for (k in c("phenotypic.loss", "phenotypic.imc", "phenotypic.muscle", "etiologic.intake", "etiologic.absorption",
    "etiologic.aggression")) {
    say(sprintf("  %-22s seed 1->%d: %s", k, seed, tab(paste(s1_crit(k), "->", fl_crit(k)))))
  }
  mf1 <- s1$facts[s1$facts$producer == PRODUCER, ]
  say("  model facts, seed 1: ", nrow(mf1), " (kept ", sum(mf1$status == "kept"), ") | seed ", seed, ": ", nrow(mf),
    " (kept ", sum(mf$status == "kept"), ")")
}

saveRDS(list(stays = stays, status = status_of, facts = facts, evidence = evidence, criteria = FC, verdicts = FV,
  review_decision = dec, lost = lost, seed = seed, commit = commit), file.path(out_dir, paste0("compare-64", sfx, ".rds")))
writeLines(iconv(log, "UTF-8", "ASCII//TRANSLIT"), file.path(out_dir, paste0("compare", sfx, ".log")))

clip <- function(x, n = 180) ifelse(nchar(x) > n, paste0(substr(x, 1, n), "..."), x)
explain <- function(id, indent = "      ", depth = 0L) {
  f <- facts[facts$fact_id == id, ]
  head <- sprintf("%s%s %s %s%s%s %s%s%s [%s %s]%s", indent, id, f$concept,
    ifelse(is.na(f$value), "", format(round(f$value, 2))), ifelse(is.na(f$unit), "", paste0(" ", f$unit)),
    ifelse(is.na(f$value_chr), "", paste0(" ", f$value_chr)), ifelse(is.na(f$reference), "", f$reference),
    ifelse(is.na(f$span_lo), "", sprintf(" %g-%g d", f$span_lo, f$span_hi)),
    ifelse(f$bound == "lower", " (floor)", ""), f$producer, f$status,
    ifelse(is.na(f$reason), "", paste0(": ", f$reason)))
  e <- evidence[evidence$fact_id == id, ]
  lines <- c(head, if (!is.na(f$note) && depth == 0L) paste0(indent, "  note: ", clip(f$note, 240)))
  for (i in seq_len(nrow(e))) {
    lines <- c(lines, if (e$kind[[i]] == "fact") {
      if (depth < 3L) explain(e$parent_fact_id[[i]], paste0(indent, "  <- "), depth + 1L)
    } else {
      sprintf("%s  [%s] \"%s\"", indent, ifelse(is.na(e$fragment_id[[i]]), e$record_ref[[i]], e$fragment_id[[i]]), clip(e$quote[[i]]))
    })
  }
  lines
}
report <- character()
for (n in seq_along(batch_ids)) {
  id <- batch_ids[[n]]
  report <- c(report, "", strrep("=", 78),
    sprintf("#%d  %s  %s  age %g  sex %s | extraction %s", n, id, group_of[[id]], stays$age[[n]], stays$sex[[n]], status_of[[id]]),
    sprintf("review decision: %s", dec[[id]]),
    sprintf("fact layer:  %s / %s / %s / %s", fl_axis("phenotypic")[[n]], fl_axis("etiologic")[[n]], fl_axis("diagnosis")[[n]], fl_axis("severity")[[n]]),
    sprintf("catabolism:  %s / %s / %s / %s", axis_of(cat64, "phenotypic")[[n]], axis_of(cat64, "etiologic")[[n]],
      axis_of(cat64, "diagnosis")[[n]], axis_of(cat64, "severity")[[n]]),
    sprintf("closed:      %s / %s / %s / %s", closed_axis("phenotypic")[[n]], closed_axis("etiologic")[[n]],
      closed_axis("diagnosis")[[n]], closed_axis("severity")[[n]]),
    sprintf("luna:        %s / %s / %s / %s   (phenotype / etiology / diagnosis / severity)", axis_of(luna, "phenotypic")[[n]],
      axis_of(luna, "etiologic")[[n]], axis_of(luna, "diagnosis")[[n]], axis_of(luna, "severity")[[n]]))
  cr <- FC[FC$EVTID == id, ]
  for (i in seq_len(nrow(cr))) {
    report <- c(report, sprintf("  %-22s %s", sub("^[^.]+[.]", "", cr$criterion[[i]]), cr$state[[i]]))
    if (nzchar(cr$facts[[i]])) for (fid in strsplit(cr$facts[[i]], ",")[[1L]]) report <- c(report, explain(fid))
  }
  mine <- facts[facts$EVTID == id & facts$producer != "biology-selector", ]
  if (nrow(mine)) {
    report <- c(report, "  every fact of the stay:")
    for (fid in mine$fact_id) report <- c(report, explain(fid))
  }
}
writeLines(iconv(report, "UTF-8", "ASCII//TRANSLIT"), file.path(out_dir, paste0("compare", sfx, "-report.txt")))
writeLines(c("done", out_dir))
