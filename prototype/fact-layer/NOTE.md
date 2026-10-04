# Note: can the HAS grid be a page of rules over facts?

## Read first (added 4 October 2026, after both seeds)

**The verdict is about equal on the phenotype.** That is the reading fixed
before each run. Seed 1 lost 0 of the 44 stays and seed 2 lost 3, and the worse
seed decides. The sections below stay as they were written at the time. Three
statements in them overstate the result:

- **"About 1 time in 600"** (the first result) and the odds in the first
  reading treat the 44 stays as 44 independent tries.
- **"3 of 88 stay-runs against 12 of 88"** pools the stays the same way.
- **"6 of 64 against 12 of 60"** compares the fact layer's two seeds with two
  DENUT runs that differed in their aggression text. DENUT's like-for-like
  seed repeat changed the phenotype on 3 of 22 stays. That compares
  `…-closed-20261001-s1` with `…-closed-20261002-s2`. So the two shapes are about
  as stable as each other.

**The stays are not independent within a run.** The same seed went out with
every request, so llama-server sampled every stay from the same random stream,
and one seed tilts all 64 stays together. Seed 2 wrote fewer output tokens than
seed 1 on 57 of the 64 stays, at a median ratio of 0.78. Its prompts were
identical to seed 1's on all 64, matched by stay. DENUT + Bonsai's own seed 2
was shorter on 12 of its 23 stays, at a median ratio of 0.99. So the direction
depends on the prompt, but every stay shares the tilt. Each seed is one draw.
The three stays seed 2 lost are among the shortest records: ranks 55, 59 and 62
of 64 by input size.

**For a future run,** derive each stay's seed from the stay and the run number,
so that one run is 64 draws.

**What the shape still offers** is traceability: every answer resolves to
quoted facts. It also fails one fact at a time: a bad field costs one fact
instead of a whole stay, and no stay failed in either seed. Neither is a gain in
accuracy.

## The real test (written on 4 October 2026, before the run)

Everything in the sections further down reads facts that luna had already
extracted. Matching luna's 512 values only shows that nothing was lost in the
repackaging. It is a no-regression check, not a result. The real test extracts
every fact from scratch with the local model, and compares the result with
DENUT + Bonsai on the same 64 stays, the same documents and the same settings.

**What runs.** `extract_every_fact.R` asks Ternary-Bonsai-2-27B on the local
llama-server (seed 1, 2048 thinking tokens) for every fact the grid reads:

- weights, with their date or their reference (usual, before the illness);
- heights, and the BMIs and weight losses the record writes;
- intake, artificial feeding, absorption and muscle measurements;
- the aggression's conditions, with their dates.

The model copies numbers and words and cites them. R reads the times and the
amounts, and does every calculation (`every_fact.R`). Albumin comes from the
lab table. No luna fact is used. The contract applies: a stay with documents
and no fact fails, and a category or a qualifier must be named in what its fact
cites. The grid now computes intake, absorption and muscle from facts too, so
the model judges no criterion.

**The aggression's time rule**, fixed before the run as the merged DENUT text
has it (redsan-coding `13c92ea`). An acute aggression counts if it began before
admission and is still active at admission. It also counts if it is dated
inside the period over which a documented weight loss is measured. Antibiotics
for "plusieurs semaines" are read as 21 days or more, provisionally.

**The prediction I was given, and why it cannot decide.** It said: "the fact
layer recovers the phenotype on most of the 9 stays where DENUT + Bonsai lost
it by filling the form badly." Those 9 stays are #16, #23, #28, #36, #44, #51,
#57, #61 and #63. They are where the closed-list run of 1–2 October lost a
phenotype that luna found.

The next DENUT + Bonsai run, the catabolism run of 2 October, asked the same
phenotype question; only the aggression wording had changed. It already found
the phenotype on 8 of the 9. Only #51 stayed lost, and you judged #51 not
justifiable. Among the stays you judged justifiable, the two runs' losses do not
overlap at all. Stays picked because one run failed on them will do better on
the next run whatever is tested, like patients picked for one high
blood-pressure reading. I will report the 9, but they cannot separate the two
shapes.

**The reading, decided now.** Take the 44 stays where luna established the
phenotype and you judged the code justifiable. For each method, count how many
of them it leaves without the phenotype: unknown, not met, or failed. DENUT +
Bonsai left 5 in the catabolism run and 7 in the closed-list run, on different
stays each time: about 6 of 44.

- **Clearly better, the shape earns its place:** 0 or 1 lost.
- **About equal, its value is only traceability and generality:** 2 to 10 lost.
- **Worse, rethink it:** 11 or more lost.

At DENUT's rate, 1 or fewer happens by chance about 1 time in 80, and 11 or
more about 1 time in 32. Anything between them, one run cannot separate from
DENUT. This test can only see a large difference.

**Reported beside it, with no threshold:** stay by stay, the phenotype and
etiology axes, the diagnosis and the severity. Each is compared with both DENUT
runs, with luna r2 and with your decision column. Bonsai changes 12 of 60
phenotype answers between its two DENUT runs. A smaller difference between the
fact layer and DENUT means nothing.

**My own expectation: about equal.** Most of DENUT's losses are grounding
refusals: a number or a duration missing from the fragment the model cited. The
fact layer keeps that same rule, so it should lose stays the same way. It could
do better in one place. DENUT failed three whole stays (#8, #48, #52) on a single
empty field; here, a bad field fails one fact.

**Result, run on 4 October.** The extraction is `every-fact-bonsai-64.rds`
(question `e85da1a3`, chat settings `29aab700`, the same as both DENUT runs').
The comparison is `compare.log`, from `compare.R` at `16ad89c` on a clean tree.
Both are in the output folder named at the top of the next section.

**Clearly better, by the reading fixed before the run.** On the 44 stays where
luna found the phenotype and you judged the code justifiable, the fact layer
found it on all 44. DENUT + Bonsai lost it on 5 and on 7. At DENUT's rate,
losing none happens by chance about 1 time in 600. My expectation, about equal,
was wrong.

- **It does not lean on the new rules.** On 40 of the 44 stays, weight loss or
  BMI established the phenotype. The other 4 rest on muscle, and so did luna's
  answer on the same 4.
- **It agrees with luna on 62 of the 64 phenotype answers.** The two DENUT runs
  agree with luna on 56 of 61 and on 51 of 62. The two exceptions, #39 and #46,
  are stays where the fact layer found a phenotype luna did not; you judged both
  justifiable.
- **No stay failed.** DENUT failed 3 stays outright (#8, #48, #52), each on a
  single field of its form. Here a bad field costs one fact. R refused 313 of
  the 1,274 facts the model gave, mostly conditions whose citations never name
  their category, and every stay still kept enough facts to decide.
- **A refused number was a wrong pointer, not an invention.** Of the 23
  numbers refused because the fragment they cite does not hold them, 21 are
  written elsewhere in the same stay. The model pointed at the wrong line.
- **The 9 stays of the given prediction:** the fact layer found the phenotype on
  all 9. DENUT's own next run found it on 8, so they show little.
- **Same cost:** a median of 178 s per stay and 3.3 h for the 64, against 189 s
  and 3.4 h for DENUT + Bonsai.

**The diagnosis is not better, because of the etiology, not the phenotype.**
Among the 48 stays you judged justifiable, the fact layer supports the diagnosis
on 20, DENUT on 17 and on 20, and luna on 44. The aggression now follows the
merged time rule and holds on 21 of the 64 stays. Luna's 64 came from the older
wording, and from how this batch was picked. Intake is almost never
established: the record rarely writes how much was eaten, for how long, and
against what. Those are questions about the rules, and this test does not
answer them.

**What this cannot show.** It is one run of one seed. The threshold allows for
DENUT's noise, not for the fact layer's own, which nobody has measured. A
second seed would take another 3.3 h.

## The second seed (written on 4 October 2026, before the run)

You chose to run it before deciding whether the fact table becomes the engine's
output contract. Only the seed changes, from 1 to 2. The model, the question,
the documents and the rules are those of the first run, and DENUT + Bonsai's
own seed-2 run used the same change.

**The reading is the same as the first run's**, on the same 44 stays: 0 or 1
lost is clearly better, 2 to 10 about equal, 11 or more worse.

**Combined, I read the worse of the two seeds.** The shape is clearly better
only if both seeds lose 0 or 1. If seed 2 lands at 2 to 10, the first result
was partly luck, and the honest summary is about equal with better
traceability.

**Reported beside it, with no threshold:** the stays each seed lost, and how
many answers on each axis change between the two seeds. That is the fact
layer's run-to-run noise, the number the first run could not give. Bonsai
changed 12 of 60 phenotype answers between its two DENUT runs.

**Result, run on 4 October.** The extraction is `every-fact-bonsai-64-s2.rds`
(question `e85da1a3`, chat settings `fa10b439`, the same as DENUT + Bonsai's
own seed-2 run). The comparison is `compare-s2.log`, from `compare.R` at
`ae5d238` on a clean tree. Seed 1's `compare.log`, rerun at the same commit,
is unchanged apart from its header.

**About equal, by the reading fixed before the run.** Seed 2 left 3 of the 44
stays without the phenotype: #10, #13 and #38. Seed 1 left none. The worse
seed decides, so the shape's value on this test is traceability and
generality, not a measured gain.

- **The pooled picture still leans the fact layer's way.** Over its two seeds
  it lost 3 of 88 stay-runs; DENUT + Bonsai lost 12 of 88 over its two runs.
  The rule was fixed to read the worse seed, and it stands.
- **The three were lost differently from DENUT's.** No stay failed, and no
  weight was refused for a wrong number. On #10 and #13 the model returned no
  weight, height, BMI or loss at all, and a single condition. On #38 it gave a
  weight, a height and a BMI that cite no fragment, and R refused them. These
  are answers that came back almost empty, not grounding refusals.
- **The fact layer's own noise, the number seed 1 could not give:** 6 of 64
  phenotype answers change between its seeds, against 12 of 60 between
  DENUT's two runs. The diagnosis changes on 19 of 64, against 22 of 60. The
  etiology is the noisy part: 14 aggressions met at seed 1 are unknown at
  seed 2, and 5 go the other way.
- **This seed did less work.** It returned 1,060 facts against 1,274, with a
  median of 128 s per stay against 178 s, 2.4 h for the 64.
- **The 9 stays of the given prediction:** the phenotype found on all 9 again.

## The first experiment

Every number below comes from `run.R` at commit `efa56fe`, run from a clean tree
over the 64 test stays, except where a number is marked as before the contract
(commit `7b77222`). The results are in
`%APPDATA%/R/data/R/extractionengine/fact-layer-prototype/summary.log`. The
model's facts come from `extract_atomic.R` and are saved in
`atomic-bonsai-64.rds` in the same folder. The question it asked has digest
`889fcea2`, which is `atomic.R` at `b24cbe3`. The model was
Ternary-Bonsai-2-27B on the local llama-server, with the settings of the bonsai
run it is compared against: seed 1, 2048 thinking tokens. No document left the
machine. `report.txt`, in the same folder, shows each stay's facts, quotes and
decisions, for a reader on this machine.

## The answer from the first experiment

**Yes, with two conditions.**

`grid.R` writes the whole grid in 75 lines of code: the three bands, the
verdict, and the aggression closed list. Run over the facts the luna run
extracted, it gives luna's answer on all 512 computed and structured criteria.
It also gives the same diagnosis and severity on all 64 stays. Each of the 234
facts a decision rests on resolves to a quote or a source row.

The experiment used the same local model, the same documents and the same
settings throughout. Asked to judge, the model found aggression in 23 of the 61
stays it answered; its pass failed on the other 3. Asked only to list facts,
with R applying the closed list, it also found aggression in 23 stays before the
contract below. In exchange, every answer now names its branch and the quoted
facts behind it.

**Two conditions**, from a review of the stays by the redsan-coding session,
which I checked against these files, and which are now written into the
contract (R only, no new model call):

1. **An empty list is a failure, not a finding.** On stay #13 the model
   reasoned for about 2,000 tokens and returned no fact. That stay is the
   clearest acute aggression among the nutritionist's cases: diabetes revealed
   by a ketoacidosis, a bacteraemia, intensive care. It was counted as answered,
   which repeats exactly the silence DENUT could not see. A stay with documents
   and no fact must fail.
2. **A category is a claim, like a stage.** Its word must be in what the fact
   cites, or the fact is refused.

**Under the contract**, #13 fails instead of passing as "nothing found", and 75
of the model's 402 facts are refused because their citations never name their
category, the six false diabetic crises among them. Stay #2 then drops out:
its only qualifying fact was one of those crises. The rule over the model's facts
finds aggression in 18 stays, against 23 for the same model judging. The two
methods agree on 43 of the 60 stays both answered. On the 23 stays where
aggression was expected to hold, the nutritionist's 13 and the 10 controls,
extracting finds 8 and judging 11; adding the regex and PMSI facts brings
extracting to 11. Stay #13 is in neither count. The category word lists were
written without reading a document, so some of the 75 refusals are the lists'
fault, not the model's: heart failure (5), chronic inflammatory disease (6) and
kidney disease (3) are the ones to check first in `report.txt`. That calibration
is the next piece of work.

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

**What R did.** It refused 88 of the 402 facts: 75 whose citations never name
their category, 6 carrying a stage and 5 a duration that no cited fragment
contains, and 2 that cited nothing. Then it applied the closed list. It reads the stage itself: NYHA III or IV, GOLD 3 or 4,
kidney failure stage 4 or 5 or a GFR under 30, a tumour that is not pTa or in
situ. It applies the timing rule: an acute condition that began during the stay
does not count. It requires an inflammatory or infectious chronic disease to be
active.

**Where judging and extracting disagree, the facts say why.** On 12 stays bonsai
judged aggression met and the rule did not. On those stays the model's kept
facts hold only categories the list excludes: a simple infection, a metabolic
disorder, a stroke, a heart failure with no written class. Or they hold cancers
filed as history, or a sepsis that began during the stay. On 5 stays the rule
found aggression and bonsai's judgement did not. A judgement that disagrees can
only be argued with. A fact that disagrees can be checked against its quote.

**Where the model errs now: filing.** Before the contract, a crude screen asked
whether the fragments a fact cites contain any word of its category, and for 73
of 284 kept facts they did not. The word lists were written without reading a
document, so some of these are the lists' fault. One category stands out: 6 of 8 "diabetic crisis" facts never
say acidocétose, cétose or hyperosmolaire. Read by the redsan-coding session,
they are three type 2 diabetes named as a diagnosis, a severe hypoglycaemia
(which the text excludes), a lactic acidosis, and a "déséquilibre du diabète".
One of them was what made stay #2 meet the acute branch, before the contract
refused it.

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
  and all 8 are refused: 6 for the stage, 2 first for an unnamed category. On
  stay #2 that included the heart-failure class again. A refused fact never reaches a rule.
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
  derived fact in days that cites its infection; 17 were derived, and one
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
  in 11. The model's own criterion answers enter as facts asserted by `model`.
  `judged()` is the only place a rule reads an answer instead of computing one.
  The experiment above retires that for aggression.
- **Silence.** No rule can see a fact nobody extracted, so recall is checked
  beside the producers. Every stay's text writes a weight or a BMI with a
  number, and luna left one stay with no anthropometric fact. The model left
  stay #13 with no fact at all, which is the first condition above. The regex
  and PMSI producers meet aggression on 4 stays where the model's facts do not,
  and the model on 13 where they do not. Two producers that disagree point at
  what one of them missed. But the regex errs too: on stay #14 it read a sepsis
  from years before as current, and that alone made the stay supported and
  severe. It now marks a mention as past history when a year older than the
  admission sits near it, or is the only kind of year its fragment holds: 14
  mentions instead of 5, and #14 no longer meets aggression.

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
fails, and a category must be named in what its fact cites. The real test at
the top is the evidence that matters most. With the same local model and the
same documents, the shape kept the phenotype on every stay where DENUT + Bonsai
lost it. On the diagnosis it is no worse, and it is held back by the etiology
rules, not by the shape. The shape expressed
the whole grid, kept every answer of the existing pipeline, and with a local
model extracting, it judged aggression as often as that model judging directly.
Each answer can now be traced to quoted facts, and each error can be seen for
what it is: a misfiled category, a stale status, a refused stage.
