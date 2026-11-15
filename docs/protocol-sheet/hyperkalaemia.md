# Hyperkalaemia (E87.5) as a protocol sheet

Status: first draft, never run. **Every clinical choice here is mine and needs
your confirmation.** Each one is marked `assumed: yes` and listed at the end.

The repo has no real hyperkalaemia protocol. It has a lab-only contract test
from June 2026 (K+ > 5.0 mmol/L, deleted since) and the vignette's toy example
(K+ > 5.2). Neither asks whether the hyperkalaemia was managed.

## The sheet

```yaml
protocol:
  name: Hyperkalaemia
  question: >
    Which stays had a hyperkalaemia that was found and managed,
    and is E87.5 coded for them?
  target_code: E87.5
  status: draft, thresholds not confirmed

population:
  unit: stay
  include: age >= 18, discharged in 2024
  assumed: yes

facts:
  potassium:
    type: lab
    code: [K.K]
    unit: mmol/L
    plausible: [1, 10]
    ignore_when: sample flagged haemolysed
    assumed: yes
    note: >
      K.K is the code in the vignette's invented data. The real code or label,
      and the field that flags a haemolysed sample, are to confirm.

  e875_coded:
    type: code
    system: CIM-10
    codes: [E87.5]
    complete: yes                 # no code means truly not coded

  dialysis_act:
    type: code
    system: CCAM
    codes: []                     # to list
    complete: yes
    assumed: yes

  hyperkalaemia_named:
    type: mention
    find: words
    words: [hyperkaliemie, hyperK]

  lowering_treatment:
    type: mention
    find: both
    means: a treatment given to lower potassium
    words:
      - kayexalate
      - polystyrene sulfonate
      - resikali
      - lokelma
      - zirconium
      - veltassa
      - patiromer
      - insuline glucose
      - salbutamol
      - gluconate de calcium
      - bicarbonate
    assumed: yes
    note: >
      Salbutamol and bicarbonate have other uses. With find: both, the words
      find the mention and the model says whether it is given for potassium.

  causal_drug_stopped:
    type: mention
    find: model
    means: >
      a drug stopped or reduced because of the potassium: ACE inhibitor,
      sartan, spironolactone, potassium supplement
    assumed: yes

criteria:
  measures:
    highest_potassium: {take: highest, of: potassium}
    first_high:
      take: earliest
      of: potassium
      where: [value > 5.5]

  lab_high:
    test: highest_potassium > 5.5
    assumed: yes
    note: The lab's upper normal limit is nearer 5.0. PMSI practice may differ.

  lab_severe:
    test: highest_potassium >= 6.5
    assumed: yes

  treated:
    any_of:
      - present: lowering_treatment
        where: [not history]      # history = usual home treatment
      - present: dialysis_act
      - present: causal_drug_stopped

  monitored:
    present: potassium
    at_least: 2
    dated_within: {after: first_high, days: [0, 2]}
    assumed: yes
    note: Does monitoring alone count as management for a DAS?

  managed:
    any_of: [treated, monitored]

answer:
  outputs:
    justified: lab_high AND managed
    opportunity: justified AND NOT e875_coded
    to_review: e875_coded AND NOT lab_high
  report: [highest_potassium, lab_severe, hyperkalaemia_named]
```

## Does it fit the format?

Mostly yes. This protocol is close to the first sketch. It needed four things
the sketch did not have.

1. **Three answers.** A stay with no potassium result must answer `unknown`,
   not "not justified". With two answers, the 2024 count would silently mix
   "normal potassium" with "never measured".
2. **A complete source.** "Not coded" must be a real negative, or `opportunity`
   can never be met. Hence `complete: yes` on the code facts.
3. **A value beside the answer.** A DIM doctor wants the highest potassium next
   to each stay. Hence `report`.
4. **One fact dated against another.** `monitored` counts results in the 48
   hours after the first high one. The window starts at a fact, not at
   admission.

## A real limit, whatever the format

I first wrote "treated within 48 hours of the high result". I removed it. A
treatment read from a discharge letter carries the letter's date, not the date
the drug was given. So text cannot say when the patient was treated. That test
needs the drug administration table, if EDSAN has one I can use. I do not know
whether it does.

## Assumptions for you to confirm

| # | assumption | why it matters |
| --- | --- | --- |
| 1 | threshold 5.5 mmol/L | 5.0 would add many mild, untreated cases |
| 2 | severe at 6.5 mmol/L | reported only, changes no answer |
| 3 | haemolysed samples are ignored | false high results are common |
| 4 | the treatment word list | a missing drug is a missed stay |
| 5 | monitoring alone counts as management | my reading of the DAS rule: the condition needed extra diagnostic or therapeutic care |
| 6 | the 48-hour monitoring window | arbitrary |
| 7 | usual home Kayexalate does not count | chronic treatment, no new episode |
| 8 | chronic dialysis patients are kept | their hyperkalaemia may be routine |
| 9 | adults only, discharges of 2024 | copied from the sketch |
| 10 | lab code K.K | invented data, real code unknown |

I did not check the tariff weight (CMA level) of E87.5.
