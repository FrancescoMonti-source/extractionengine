# The HAS 2021 denutrition grid, written as rules over facts.        PROTOTYPE
#
# Rules read the fact table and the stay's age and sex, nothing else: no
# document, no source table, no model. The fiche's wording for each criterion
# is in redsan-coding's has_denutrition_criteria.csv, under the same names.

# What the grid measures. A measure is one value per stay, or a floor on it.
bmi        <- lowest("bmi", drop = historical, prefer = derivation == "derived")
albumin    <- lowest("albumin")
loss_1m    <- change("weight_loss", window = c(28, 31))    # days; a shorter span is a floor
loss_6m    <- change("weight_loss", window = c(180, 184))
loss_usual <- change("weight_loss", against = c("usual", "before_disease"))

losing <- function(month, six, usual) any_of(loss_1m >= month, loss_6m >= six, loss_usual >= usual)

# Tests note 1: the adult moderate loss band is closed at its top by
# interpretation, and a floor cannot refute that top, so it is not asked to.
grading <- function(q, ...) band(q, ..., upper_unless_refuted = TRUE)

iotf <- function(curve) function(stay) iotf_cutoff(stay$age, stay$sex, curve)

has_grid <- function(aggression = judged()) {
  etiologic <- list(intake = judged(), absorption = judged(), aggression = aggression)
  list(
    adult = band_rules(age = c(18, 70),
      phenotypic = list(loss = losing(5, 10, 10), imc = bmi < 18.5, muscle = judged()),
      etiologic  = etiologic,
      moderate   = list(imc = band(bmi, above = 17, below = 18.5),
                        loss = any_of(grading(loss_1m, from = 5, below = 10),
                                      grading(loss_6m, from = 10, below = 15),
                                      grading(loss_usual, from = 10, below = 15)),
                        albumin = band(albumin, above = 30, below = 35)),
      severe     = list(imc = bmi <= 17, loss = losing(10, 15, 15), albumin = albumin <= 30)),

    age70 = band_rules(age = c(70, Inf),
      phenotypic = list(loss = losing(5, 10, 10), imc = bmi < 22, muscle = judged()),
      etiologic  = etiologic,
      moderate   = list(imc = band(bmi, from = 20, below = 22),
                        loss = any_of(grading(loss_1m, from = 5, below = 10),
                                      grading(loss_6m, from = 10, below = 15),
                                      grading(loss_usual, from = 10, below = 15)),
                        albumin = albumin > 30),
      severe     = list(imc = bmi < 20, loss = losing(10, 15, 15), albumin = albumin <= 30)),

    child = band_rules(age = c(0, 18),
      phenotypic = list(loss = losing(5, 10, 10), imc = bmi < iotf("185"),
                        channel = judged(), muscle = judged()),
      etiologic  = etiologic,
      moderate   = list(imc = band(bmi, above = iotf("17"), below = iotf("185")),
                        loss = any_of(grading(loss_1m, from = 5, upto = 10),
                                      grading(loss_6m, above = 10, upto = 15)),
                        channel = judged()),
      severe     = list(imc = bmi <= iotf("17"), loss = any_of(loss_1m > 10, loss_6m > 15),
                        channel = judged(), stature = judged()))
  )
}

# Diagnosis: one phenotypic and one etiologic criterion. Severity only then:
# one severe criterion settles it, otherwise one moderate one, otherwise it is
# indeterminate. Unknown grading criteria are named when they could still raise
# or establish the grade.
verdict <- function(criteria) {
  axis <- tapply(criteria$state, criteria$axis, kleene_or)
  both <- kleene_and(axis[c("phenotypic", "etiologic")])
  diagnosis <- c(met = "supported", not_met = "not_supported", unknown = "indeterminate")[[both]]
  severity <- if (diagnosis != "supported") NA_character_ else
    if (axis[["severe"]] == "met") "severe" else if (axis[["moderate"]] == "met") "moderate" else "indeterminate"
  could_change <- switch(paste(severity), moderate = "severe", indeterminate = c("moderate", "severe"), NULL)
  open <- criteria$state == "unknown" & criteria$axis %in% could_change
  data.frame(EVTID = criteria$EVTID[[1L]], phenotypic = axis[["phenotypic"]],
    etiologic = axis[["etiologic"]], diagnosis = diagnosis, severity = severity,
    severity_unresolved = if (any(open)) paste(criteria$criterion[open], collapse = ", ") else NA_character_)
}

# The aggression criterion as the closed list of 2026-10-01, over facts from any
# producer. Absent on purpose: the dietitian's box (never enough alone), a
# stroke, a simple infection, a fracture, a metabolic disorder, a stage the
# record does not write, and any CRP. A single rifampicin is no regimen: it also
# treats a staphylococcal bone infection for weeks, or a cholestatic itch.
nyha_3_4 <- function(s) grepl("(nyha|classe|stade)\\W{0,6}(iii|iv|3|4)\\b", fold(s))
gold_3_4 <- function(s) grepl("gold\\W{0,6}(3|4|iii|iv)\\b|severe", fold(s))
not_invasive <- function(s) grepl("\\bp?ta\\b|\\bp?tis\\b|in situ|\\bcis\\b|non infiltrant|bowen", fold(s))
ckd_4_5 <- function(s) {
  gfr <- suppressWarnings(as.numeric(sub(",", ".", sub(
    "^.*?(dfg|clairance|filtration|mdrd|ckd.?epi)\\D{0,20}?([0-9]+([.,][0-9]+)?).*$", "\\2", fold(s), perl = TRUE))))
  grepl("^n18[45]|stade\\W{0,6}(4|5|iv|v)\\b|<\\s*30", fold(s)) | (gfr < 30) %in% TRUE
}
aggression_branches <- list(
  acute     = any_of(has(c("sepsis", "icu_organ_failure", "major_surgery", "major_trauma_or_burn",
                           "severe_pancreatitis", "diabetic_crisis", "deep_infection"),
                         !historical & !onset %in% "during_stay"),
                     has("antibiotic_course", value >= 21 & !historical)),  # "plusieurs semaines": 3+
  chronic   = any_of(has("heart_failure", nyha_3_4(value_chr)), has("copd", gold_3_4(value_chr)),
                     has("chronic_kidney_disease", ckd_4_5(value_chr)),
                     has(c("cardiac_cachexia", "repeated_hf_decompensation", "home_oxygen_or_niv",
                           "dialysis", "cirrhosis"), !historical),
                     has(c("chronic_inflammatory_disease", "chronic_infection"), activity %in% "active"),
                     has("antituberculous_drug", !historical, at_least = 2, distinct = value_chr)),
  malignant = has("malignancy", !historical & !not_invasive(value_chr))
)
aggression_from_facts <- do.call(any_of, aggression_branches)
