# Note: can the HAS grid be a page of rules over facts?

Every number below comes from `run.R` at commit `7b77222`, run from a clean tree
over the 64 test stays. The results are in
`%APPDATA%/R/data/R/extractionengine/fact-layer-prototype/summary.log`. The
model's facts come from `extract_atomic.R` and are saved in
`atomic-bonsai-64.rds` in the same folder. The question it asked has digest
`889fcea2`, which is `atomic.R` at `b24cbe3`. The model was
Ternary-Bonsai-2-27B on the local llama-server, with the settings of the bonsai
run it is compared against: seed 1, 2048 thinking tokens. No document left the
machine. `report.txt`, in the same folder, shows each stay's facts, quotes and
decisions, for a reader on this machine.

## The answer

**Yes, with two conditions.**

`grid.R` writes the whole grid in 75 lines of code: the three bands, the
verdict, and the aggression closed list. Run over the facts the luna run
extracted, it gives luna's answer on all 512 computed and structured criteria.
It also gives the same diagnosis and severity on all 64 stays. Each of the 234
facts a decision rests on resolves to a quote or a source row.

The experiment used the same local model, the same documents and the same
settings throughout. Asked to judge, the model found aggression in 23 of the 61
stays it answered; its pass failed on the other 3. Asked only to list facts,
with R applying the closed list, it also found aggression in 23 stays. The two
methods agree on 45 of the 61 stays both answered. In exchange, every answer now
names its branch and the quoted facts behind it.

**Two conditions**, from a review of the stays by the redsan-coding session,
which I checked against these files:

1. **An empty list is a failure, not a finding.** On stay #13 the model
   reasoned for about 2,000 tokens and returned no fact. That stay is the
   clearest acute aggression among the nutritionist's cases: diabetes revealed
   by a ketoacidosis, a bacteraemia, intensive care. It was counted as answered,
   which repeats exactly the silence DENUT could not see. A stay with documents
   and no fact must fail.
2. **A category is a claim, like a stage.** Its word must be in what the fact
   cites. A quarter of the model's facts cite fragments that never name their
   category (below). The prototype computed this only on the side; it belongs in
   the contract.

**What this batch cannot measure is recall against your review.** All 64 stays
were picked because luna judged aggression met, and 41 because that aggression
was doubtful: the strokes and the grey infections. Your "Justifiable" decisions
date from 12 September, before your ruling of 2 October that sends those cases
to the TIM. And reduced intake stayed unknown on 62 of the 64, so a stay you
judged justifiable may rest on intake, which nothing here reads. "15 of 48" is
therefore not a recall figure. The stays worth reading are the 13 nutritionist
cases and the 10 controls, where aggression was expected to hold.

## The shape, from zero

**A fact** is one line of a chart: "weight 62 kg, measured at admission, read in
the dietitian's letter". Each fact is one row of one table, whatever produced it:
the biology table, the PMSI, a model, a regular expression, or a rule computing
from other facts. Its columns name the stay, the concept under the study's own
name, and the value. They also hold the record's date and a small time model, the
qualifiers (negated, hypothetical, historical, family), the condition's activity
and onset, who asserted it, the producer, and whether it was kept or refused.
OMOP calls this "one shape for every fact". Here it is borrowed for one study,
and facts are built only for the concepts the study asks about.

**Evidence** is a second table. A fact read from text cites the fragments the
model was shown, by the same `evidence_id`. A fact read from a structured row
cites that row. A computed fact cites the facts it was computed from: a BMI
cites its weight and its height, and each of those cites its fragment. That is
the answer to **gap 2**. A derived value is owned by the rule that computed it,
named and versioned in `producer`, and its evidence is its operands.

**A rule** is R over facts, and nothing else. It reads no document and no source
table. The grid is written the way the fiche is: `bmi < 18.5`, `loss_6m >= 10`,
`band(albumin, above = 30, below = 35)`, `any_of(...)`. Each answer is met,
not_met or unknown, like a test that is positive, negative or not done. Each
answer carries the ids of the facts that decided it. Absence is never a
refutation: `has()` answers met or unknown, nothing else.

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
`denut_calculation.R`, and the tests CSV. In the new shape it is `grid.R`, 75
lines, on top of `rules.R`, 146 generic lines that would belong to the engine.

## The experiment: the model extracts, R judges

**What the model was asked.** One fact per condition, filed into 25 categories:
the closed list's items, plus its exclusions (a stroke, a simple infection, a
fracture, a metabolic disorder). The exclusions are there so that nothing has to
be squeezed into the nearest box that qualifies. Each fact also carries a status
(active, stable, history, suspected, excluded, family) and an onset relative to
admission. A stage or a planned treatment duration is transcribed word for word.
The model answers no criterion.

**What R did.** It refused 17 of the 402 facts. Eight carried a stage and seven
a duration that no cited fragment contains, and two cited nothing. Then it
applied the closed list. It reads the stage itself: NYHA III or IV, GOLD 3 or 4,
kidney failure stage 4 or 5 or a GFR under 30, a tumour that is not pTa or in
situ. It applies the timing rule: an acute condition that began during the stay
does not count. It requires an inflammatory or infectious chronic disease to be
active.

**Where judging and extracting disagree, the facts say why.** On 9 stays bonsai
judged aggression met and the rule did not. On those stays the model's own facts
hold only categories the list excludes: a simple infection, a metabolic
disorder, a stroke, a heart failure with no written class. Or they hold cancers
filed as history, or a sepsis that began during the stay. On 7 stays the rule
found aggression and bonsai's judgement did not. A judgement that disagrees can
only be argued with. A fact that disagrees can be checked against its quote.

**Where the model errs now: filing.** A crude screen asks whether the fragments
a fact cites contain any word of its category. For 73 of 284 facts they do not.
The word lists were written without reading a document, so some of these are
the lists' fault. One category stands out: 6 of 8 "diabetic crisis" facts never
say acidocétose, cétose or hyperosmolaire. Read by the redsan-coding session,
they are three type 2 diabetes named as a diagnosis, a severe hypoglycaemia
(which the text excludes), a lactic acidosis, and a "déséquilibre du diabète".
One of them is what makes stay #2 meet the acute branch. Used as a guard, the
screen cuts aggression from 23 stays to 18.

**A measurement belongs to R, not to the model.** Both real ketoacidoses
already have their blood gases in the bundle's biology table. The model's only
job is to find the word "acidocétose"; R then reads pH and bicarbonate as
structured facts, as it reads albumin. Where the gases are not in the bundle, as
on stay #13, the word is the only evidence. Choosing the category is the last
judgement left to the model; the word check and the lab facts take it away.

## The seven cases

- **An invented stage.** Bonsai's judging pass named a NYHA class or a GOLD stage
  in three aggression rationales, and nothing it cited holds any of them. Read as
  facts and grounded like any number, all three are refused. Asked only for
  facts, the same model again wrote stages its citations do not hold, 8 times,
  and all 8 were refused. On stay #2 that included the heart-failure class
  again. A refused fact never reaches a rule.
- **A branch the model never looked at.** On the BCGitis stay (#47), the lexicon
  finds ethambutol, isoniazid and rifampicin, and the rule "two distinct
  anti-tuberculous drugs" meets the chronic branch. Bonsai's judgement said
  not_met. The model's own facts filed the infection as *suspected*, which does
  not count, and the bladder tumour as an active malignancy staged pT1, which
  does. Both are wrong. The pT1 is the stage of the first tumour; the later
  recurrence was in situ, under maintenance BCG, with a negative recent
  cystoscopy, which the list excludes. The "suspected" comes from a question mark
  in the admission note, while the discharge letter confirms the BCGitis and the
  triple therapy started during the stay and continues at discharge. So the
  verdict "met" is right, for the wrong reason, and only the fact layer shows it.
  Two lessons. A status changes over a stay, so the latest document should
  decide it. And an infection's rule should key on a weeks-long anti-infective
  course having started, without asking for microbiological proof: BCG cultures
  are often negative.
- **A lone rifampicin is no tuberculosis marker.** On stay #13 it belongs to the
  standard anti-staphylococcal relay. The fact should be an anti-infective course
  with a start date and an end date, so that R computes its length. A course
  written "jusqu'au" a date is an end date, which the current duration check
  refuses because no duration is written.
- **Vague time.** The eight weight-loss shapes become four concepts: `bmi`,
  `weight`, `height` and `weight_loss`. Each carries a reference role, a span and
  a negation flag. One thing does not fit a row: which two weights the record
  compares. Here that pairing is a derived fact's two parents. A real producer
  must emit it as a relation between facts, as OMOP's `FACT_RELATIONSHIP` does.
  None of the 64 stays has a dated comparison, so the dated path has not run.
- **Derived values (gap 2).** 178 of the 432 decided criteria rest on a derived
  fact, and each resolves down to quotes. A planned treatment duration becomes a
  derived fact in days that cites its infection; 20 were derived, and one
  reached three weeks. When a stay documents no weight to divide a loss in
  kilograms by, that derivation is refused with the reason, twice, never guessed.
- **Label-selected analytes (gap 1).** A concept is a test over rows, not a code
  list. Albumin is `.select_albumin()`'s label test, transcribed, and a row it
  selects but the unit rejects becomes a visible refused fact. Across all 779
  stays the label test selects exactly two codes, `ALBT.ALBT1` (656 stays) and
  `ALBS.ALBS1` (7). On this corpus a two-code list would have done the same job.
- **Judgements.** The dietitian's box is a judgement she wrote in the record. It
  enters as a fact asserted by `dietitian` (41 stays), and the aggression rule
  ignores it. Of those 41 stays, the rule over the model's facts meets aggression
  in 16. The model's own criterion answers enter as facts asserted by `model`.
  `judged()` is the only place a rule reads an answer instead of computing one.
  The experiment above retires that for aggression.
- **Silence.** No rule can see a fact nobody extracted, so recall is checked
  beside the producers. Every stay's text writes a weight or a BMI with a
  number, and luna left one stay with no anthropometric fact. The model left
  stay #13 with no fact at all, which is the first condition above. The regex
  and PMSI producers meet aggression on 4 stays where the model's facts do not,
  and the model on 17 where they do not. Two producers that disagree point at
  what one of them missed. But the regex errs too: on stay #14 it read a sepsis
  from years before as current, and that alone made the stay supported and
  severe. A keyword producer needs the past-history flag as much as the model
  does, and a year older than the admission should set it.

## Not tested

- Patient scope. The 64 stays belong to 64 different patients and the bundles
  are stays.
- The child band. It ran only on synthetic facts, and the IOTF curves applied.
- One model and one seed. The 64 stays were chosen for hard cases: strokes,
  grey infections, the nutritionist's.
- Upstream lineage: which documents a producer searched and showed. That is
  today's `audit$lineage`, and it would stay with each producer.

## The decision this leaves you

Whether to make the fact table the engine's output contract. I recommend yes,
with the two conditions written into it: a stay with documents and no fact
fails, and a category must be named in what its fact cites. The shape expressed
the whole grid, kept every answer of the existing pipeline, and with a local
model extracting, it judged aggression as often as that model judging directly.
Each answer can now be traced to quoted facts, and each error can be seen for
what it is: a misfiled category, a stale status, a refused stage.
