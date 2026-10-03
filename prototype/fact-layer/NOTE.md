# Note: can the HAS grid be a page of rules over facts?

Every number below comes from one run: `run.R` at commit `6993369`, clean tree,
over the 64 test stays, written to
`%APPDATA%/R/data/R/extractionengine/fact-layer-prototype/summary.log`. The same
folder holds `report.txt`, which shows each stay's facts, quotes and decisions
for a reader on this machine. No model was called.

## The answer

**Yes for the grid. Not yet for the engine.**

`grid.R` writes the whole grid, three bands and the verdict, in 62 lines of
code. Run over the same facts the luna run extracted, it gives the same answer
as luna on all 512 computed and structured criteria and the same phenotypic,
etiologic, diagnosis, severity and `severity_unresolved` on all 64 stays. The
other 256 criteria are the model's own judgements, read back unchanged, so their
agreement proves nothing. The centre holds: each of the 234 facts that a decision
rests on resolves to a quote or a source row, through the derived facts where
there are any. Refusals stay rows with a reason, never deletions.

The engine question is still open, because the shape moves the hard part rather
than removing it. Rules can only judge facts someone extracted. When the
aggression criterion is written as its closed list over facts from deterministic
producers only, it is met in 11 of the 64 stays. Luna's judgement says 64, and
bonsai's on the final text says 23 of 61. The rule is easy to write: it is nine
lines. Whether a local model can extract those facts well enough was not tested
here, because no model was called. That is the experiment that decides.

## The shape, from zero

**A fact** is one line of a chart: "weight 62 kg, measured at admission, read in
the dietitian's letter". Each fact is one row of one table, whatever produced it:
the biology table, the PMSI, the luna run, a regular expression, or a rule
computing from other facts. The columns say which stay the fact belongs to, the
concept under the study's own name, and the value. They also give the record's
date and a small time model, four qualifiers (negated, hypothetical, historical,
family), who asserted the fact, which producer made it, and whether it was kept or
refused. OMOP calls this "one shape for every fact". Here it is borrowed for one
study, and facts are built only for the concepts the study asks about.

**Evidence** is a second table. A fact read from text cites the fragment the
model was shown, by the same `evidence_id`. A fact read from a structured row
cites that row. A computed fact cites the facts it was computed from: a BMI cites
its weight and its height, and each of those cites its fragment. That is the
answer to **gap 2**. A derived value is owned by the rule that computed it,
named and versioned in `producer`, and its evidence is its operands.

**A rule** is R over facts, and nothing else. It reads no document and no source
table. The grid is written the way the fiche is: `bmi < 18.5`,
`loss_6m >= 10`, `band(albumin, above = 30, below = 35)`, `any_of(...)`. Each
answer is met, not_met or unknown, like a test that is positive, negative or not
done. Each answer carries the ids of the facts that decided it.

## What made a page enough

- **A measure is an interval.** A measured BMI is a point. "At least 6 % in a
  week" is `[6, ∞)` against the one-month window, like a lab result reported as
  above the assay's limit. Comparing an interval with a threshold is
  three-valued with no special case: met if every point passes, not_met if none
  does, unknown otherwise. `.compare_floor()` and most of `.test_holds()` become
  this one comparison, in `rules.R`, which knows nothing about denutrition.
- **Time is normalised once, when the fact is built.** A timed loss carries
  bounds on the days it spans. "en 1 mois" filed `within_1m` gives `[28, 31]`. A
  shorter span gives `[0, 31]`, which only floors the month. The grid then says
  `change("weight_loss", window = c(28, 31))` and never parses a word. OMOP gives
  time one free-text field, `term_temporal`, and that is too thin for this grid.
- **The selection policies are one line each.** "Drop BMIs the record dates
  before admission, prefer the computed one, take the lowest" is
  `lowest("bmi", drop = historical, prefer = derivation == "derived")`. Today it
  sits inside `.select_metric_candidates()`.
- **The one interpretation the fiche does not state now sits on the page.** Note
  1 of the tests CSV closes the adult moderate loss band at its top. A floor
  cannot refute that top, so it is not asked to. Today that rule is a line deep
  in `.test_holds()`. Here it is `grading()`, with its reason written above it.

Beside the comparator: `denut_extraction_specs.R` has 224 lines of code. It
publishes nine values per stay and contains no grid. The grid lives in
redsan-coding: `denut_grid.R` (377 code lines), the selection half of
`denut_calculation.R`, and the tests CSV. In the new shape that is `grid.R`, 62
lines, on top of `rules.R`, 145 generic lines that would belong to the engine.

## The seven cases

- **An invented stage.** Bonsai named a NYHA class or a GOLD stage in three
  aggression rationales, and in each case nothing the model cited holds it. In
  two of those stays no visible document mentions NYHA at all. Read as facts and
  grounded like any number, all three are refused (summary.log, "STAGES"). One
  was on a stay bonsai answered `met`. A refused fact never reaches a rule. The
  package already applies this check to weights. Here it is one rule applied to
  every value a model reads.
- **A branch the model never looked at.** On the BCGitis stay, the lexicon
  finds ethambutol, isoniazid and rifampicin nine times. The rule "two distinct
  anti-tuberculous drugs, not historical" meets the chronic branch. Bonsai
  answered not_met. Nothing had to notice the infection. A clinical correction
  made while writing it: one rifampicin on its own is no regimen. It also treats
  a staphylococcal bone infection for weeks, or a cholestatic itch. On a second
  stay a lone rifampicin now meets nothing. Telling those cases apart needs a
  duration fact, which no producer here emits.
- **Vague time.** The eight weight-loss shapes become four concepts: `bmi`,
  `weight`, `height` and `weight_loss`. Each carries a reference role, a span and
  a negation flag. One thing does not fit a row: which two weights the record
  compares. Here that pairing is kept as a derived fact's two parents. A real
  producer must emit the pairing as a relation between facts. OMOP keeps a
  separate table, `FACT_RELATIONSHIP`, for exactly this. None of the 64 stays has
  a dated comparison, so the dated path is written but has not run.
- **Derived values (gap 2).** 178 of the 432 decided criteria rest on a derived
  fact: a computed BMI, a computed loss, or a loss in kilograms turned into a
  percentage. Each one resolves down to quotes. When a stay documents no weight
  at all, the kilograms-to-percent rule is refused with that reason, twice. It is
  never guessed.
- **Label-selected analytes (gap 1).** A concept here is a test over rows, not a
  code list. Albumin is `.select_albumin()`'s label test, transcribed. A row the
  label selects but the unit or the bounds reject becomes a refused fact you can
  see. One open question is now answered: across all 779 stays the label test
  selects exactly two codes, `ALBT.ALBT1` (656 stays) and `ALBS.ALBS1` (7). On
  this corpus a two-code list would have done the same job.
- **Judgements.** The dietitian's box is a judgement she wrote in the record. It
  enters as a fact asserted by `dietitian` (41 stays), and the aggression rule
  deliberately ignores it. The model's own criterion answers enter as facts
  asserted by `model`, and `judged()` is the only place a rule reads an answer
  instead of computing one. Those answers are what this shape is meant to
  retire: the model extracts, and R judges.
- **Silence.** No rule can see a fact nobody extracted, so recall has to be
  checked beside the producers, never inside the rules. Two cheap screens ran
  here. Every stay's visible text writes a weight or a BMI with a number, and the
  model left one stay with no anthropometric fact at all. The lexicon and luna's
  rationale also disagree about the lone-rifampicin stay. Neither screen proves
  an omission. Both say where to look.

## Not tested

- Model-extracted atomic facts. No model was called.
- Patient scope. The 64 stays belong to 64 different patients and the bundles
  are stays, so a rule cannot reach another stay.
- The child band. It ran only on synthetic facts, and the IOTF curves applied.
- Upstream lineage: which documents a producer searched and showed. That is
  today's `audit$lineage`, and it would stay with each producer. Facts are its
  last stage, "cited".

## The decision this leaves you

Whether to run one experiment before deciding anything about the engine: the
local 27B model extracts atomic aggression facts on these 64 stays, and the
nine-line rule is checked against your review. If its recall comes close to the
judgements, the fact table is worth making the engine's output contract. If it
does not, the grid page still works, but the work has only moved into
extraction.
