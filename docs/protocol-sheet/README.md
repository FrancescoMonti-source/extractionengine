# Protocol sheet: paper test on two protocols

Date: 15 November 2026. Status: a paper test. No code was written or changed.

## What this is

A protocol sheet is a short structured form that states a protocol in words a
DIM doctor can check. The engine would turn it into R rules over a fact table.
This folder tests one thing: can the sheet express real protocols?

| file | content |
| --- | --- |
| `format.md` | the format: blocks, fact types, criterion shapes |
| `hyperkalaemia.md` | hyperkalaemia (E87.5), with every assumption marked |
| `denutrition.md` | the HAS denutrition grid, transcribed from the archived prototype |

## The result in short

- **Hyperkalaemia fits.** It needed four small additions to the first sketch.
- **Denutrition does not fit the first sketch.** It needed twelve additions.
  With them, the whole grid is written, in about 320 lines.
- **The criteria were the easy half.** They read like the HAS grid. The hard
  half is the `facts` block, which the sketch covered in one line per fact.
- **The format roughly doubled.** The sketch had 5 fact types and 5 criterion
  shapes. This draft has 6 fact types, 11 criterion shapes, and two new
  sub-blocks (`measures`, `thresholds`).

My reading: the idea survives, but "a few criterion shapes" was optimistic.
One comorbidity with a clean lab test fits a small format. A full clinical
grid does not.

## What did not fit

Each point says what the real logic needs, and what I added. The numbers match
the `# +n` tags in `denutrition.md`.

### In the criteria and the answer

**1. Three answers, not two.** The grid needs `met`, `not met` and `unknown`.
A weight loss nobody wrote down is unknown, not absent. The sketch's AND and OR
have two answers. Added: three-valued answers everywhere, `refuted_by` (a
stated denial makes a criterion not met), and `any_measured` (an OR that skips
the parts nobody measured). **This is the most important point.** It also
applies to hyperkalaemia: no potassium result must not read as "normal".

**2. Which value.** A stay has several BMIs. The rule is: take the lowest,
ignore those dated before admission unless nothing else exists, prefer the
computed one. The sketch had "at least once" only. Added: a `measures`
sub-block.

**3. Values known only as "at least".** "Lost 4 kg in a week" proves at least
some loss over a month. It cannot prove the loss stayed under 10 %. Such a
value can confirm a threshold and never refute it. Added: lower bounds inside
measures, and one special flag for the moderate band
(`lower_bound_cannot_refute_top`). That flag is an interpretation the HAS text
does not state.

**4. Thresholds that depend on the patient.** BMI cut-offs change with age
band. Muscle cut-offs change with sex. Children use the IOTF curves, a table by
age and sex. Added: `strata`, a per-stratum value for a criterion, and a
`thresholds` sub-block.

**5. Change over a vague period.** The sketch's time window assumes dated
events. Text gives periods: "en 1 mois", "depuis janvier". Added:
`largest_change` with `over_days`. The engine reads the words as a range of
days.

**6. One fact dated against another.** An acute aggression counts if it falls
inside the period a weight loss covers. A loss can be computed from two weights
the record compares. Hyperkalaemia needs it too: results after the first high
one. Added: `dated_within`. The pairing of two weights has no clean form yet.

**7. An answer in stages, with several outputs.** The verdict is not one
yes or no. It is a diagnosis, then a severity (severe if any severe criterion,
otherwise moderate, otherwise indeterminate), then the list of unknowns that
could still raise the grade. Added: several `outputs`, `first_of`, `only_if`,
and `report`.

**8. Criteria nobody can compute.** Two child criteria (growth channel,
stature) were judged by the model in the prototype. Added: a `judgement` fact
and a `judged` shape. This is an escape hatch. It brings back what the fact
layer was built to remove: an answer you can only argue with, not check.

### In the facts

**9. Computed facts.** A BMI from a weight and a height. A loss in % from two
weights. A treatment length in days. Each must cite its operands, and be
refused when one is missing. Added: the `computed` type.

**10. Facts with details.** A weight has a role (current, usual, before the
illness). A condition has a status, an onset and a stage. The sketch's "text
mention" has a name and nothing else. Added: `attributes` with closed lists.
One part still does not fit: the stage. The rule "NYHA III or IV" is today a
regular expression over copied words. In a sheet it should be a closed value
(`nyha: 3`), filled by the model or by the engine. That changes what the model
is asked.

**11. Categories that exist so nothing is misfiled.** Seven of the 25 condition
categories never count: stroke, simple infection, fracture. They exist because
a model with no honest place for a condition files it in the nearest one that
counts. Added: `recorded_only`. The format takes it easily. The worry is
different: nobody writing a new sheet would think of adding them.

**12. Sources selected by label.** Albumin is found by its label with an
exclusion list, because the lab codes are not stable. Major surgery is found by
the act's label. Added: `label` and `label_excludes`. The current engine cannot
do this yet. It is one of your open decisions.

### From hyperkalaemia

**13. Sources where absence is real.** "E87.5 is not coded" is a true negative,
because the PMSI lists every code. "No treatment mentioned" is not. Added:
`complete: yes` on a fact. Point 1 depends on it.

## What stayed out of the sheet, correctly

The engine owns these, and no sheet has to repeat them: reading French time
words as days, checking that a copied number is in its quote, failing a stay
that has documents and no fact, and the evidence trail. This is the best news
of the test. The parts that were hardest to get right are generic.

## Candid points

**The sketch hid the hard part.** It wrote `treatment: text, "kayexalate..."`.
In the real grid, half of the sheet is fact definitions, and the prompt and the
grounding word lists are still missing from my draft. See "Where I had to
cheat" in `denutrition.md`.

**The criteria block is almost the prototype's `grid.R`, line for line.**
`adult: bmi < 18.5` in the sheet, `bmi < 18.5` in R. So for criteria the sheet
buys little readability. It buys a closed vocabulary that can be checked, and
YAML that a local model writes more reliably than R. That matters only if a
local model writes sheets. Test 4 decides it.

**Generate calls to the prototype's rule functions, not free dplyr.** Three
answers and lower bounds are easy to get wrong in hand-made table code. The
prototype's `rules.R` already has them in 146 generic lines. Each shape in the
sheet maps to one of its functions.

**The format can grow back into a programming language.** Eleven shapes are
already many. The `where:` lines are a small formula language in disguise. My
suggestion: a new shape is added only when a real protocol needs it, it gets a
name, and the engine owns its meaning. No free formulas in a sheet, ever.

**A local model will not write the denutrition sheet from a question.** It
could plausibly write the hyperkalaemia one. The closed list of aggressions,
the time rule and the recorded-only categories came from your review of real
stays. For a grid of this size, expect the model to draft and a human to own
the facts block.

**Text cannot date a treatment.** A drug read in a discharge letter carries the
letter's date. Any protocol of the form "treated within N hours" needs the drug
administration table. No sheet format fixes that.

## What I did not check

- Nothing was run. The sheets are untested against data.
- `redsan-coding` is outside my reach. The denutrition sheet comes from the
  prototype at tag `archive/fact-layer-prototype-2026-10-04`. If the grid moved
  since 4 October, the sheet is behind.
- All hyperkalaemia thresholds and lists are my assumptions. See the table in
  `hyperkalaemia.md`.

## Suggested next step

Write a third protocol whose core is a change against a baseline, such as
acute kidney injury (creatinine against its earlier value). It stresses point
6, the weakest part of this draft.
