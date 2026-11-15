# Protocol sheet format (draft 0.1)

Status: a paper draft. No code reads this format yet. Nothing in `R/` changed.

A protocol sheet is a short structured form. It says what a study or an audit
asks of the hospital data, in words a DIM doctor can check. It is written in
YAML, a plain-text layout made of `name: value` lines and indented lists.

The sheet is the official record of the protocol. The engine would turn it into
R rules over a fact table. A human reviews the sheet and the read-back, never
the R code.

## The blocks

A sheet has a header and four blocks, always in this order.

| block | question it answers |
| --- | --- |
| `protocol` (header) | What is asked, about which code, from which reference text? |
| `population` | Which stays or patients? |
| `facts` | What must be found in the record, and where? |
| `criteria` | Which tests are applied to those facts? |
| `answer` | How do the criteria combine, and what is reported? |

Anything marked **[base]** below was in the first sketch. Anything marked
**[added]** had to be added to write the two real sheets. The reasons are in
`README.md`.

## Three answers, not two [added]

Every criterion answers `met`, `not met` or `unknown`. It works like a test
that is positive, negative or not done.

- **Silence is not a negative.** If no document mentions a weight loss, the
  criterion is `unknown`, not `not met`.
- A criterion is `not met` only when a fact says so: a measured value on the
  wrong side of the threshold, or a statement of absence ("poids stable").
- `any_of` is met if one part is met. It is `not met` only if every part is.
- `all_of` is `not met` if one part is. It is met only if every part is.

One exception is declared per fact, with `complete: yes`. It means the source
lists everything, so absence is a real negative. PMSI codes are complete: a
stay with no E87.5 code is truly "not coded".

## Block 1: `population`

```yaml
population:
  unit: stay                      # one answer per stay (or: patient)
  include: age >= 18, discharged in 2024
  strata:                         # [added] named groups with their own thresholds
    adult: 18 <= age < 70
    age70: age >= 70
```

The stay's age, sex, admission date and discharge date are always available.
They are not facts and need no definition.

## Block 2: `facts`

A fact is one thing the record says about one patient, with its date and a
quote or a source row as evidence. Each fact has a type from a closed list.

| type | what it is | example |
| --- | --- | --- |
| `lab` **[base]** | a row of the biology table: number, unit, date | potassium 5.8 mmol/L |
| `code` **[base]** | a CIM-10 diagnosis or a CCAM act coded in the PMSI | N18.4 |
| `number_in_text` **[base]** | a number with a unit, copied from a document | "poids 62 kg" |
| `mention` **[base]** | a condition, a treatment or an event named in a document | "choc septique" |
| `computed` **[added]** | a value calculated from other facts | BMI from weight and height |
| `judgement` **[added]** | the model's own opinion on a criterion | "growth curve broken" |

The first sketch also listed a `date` type. It is not needed: every fact
already carries a date.

Keys a fact may use:

```yaml
facts:
  potassium:
    type: lab
    code: [K.K]                   # select by lab code...
    label: potassium              # ...or by label [added]
    label_excludes: [urin]        # [added]
    unit: mmol/L
    plausible: [1, 10]            # values outside become refused facts [added]

  weight:
    type: number_in_text
    unit: kg
    attributes:                   # [added] closed lists of extra details
      role: [current, usual, before_disease, earlier]

  sepsis:
    type: mention
    find: model                   # model | words | both
    means: sepsis or septic shock
    words: [sepsis, choc septique]   # for find: words, and for grounding
    counts: yes                   # no = recorded so nothing is misfiled, read by no rule [added]

  bmi:
    type: computed
    formula: weight[current] / height^2   # the evidence is the two operands
```

Every fact read from text carries four qualifiers: `negated`, `hypothetical`,
`history`, `family`. A criterion ignores negated, hypothetical and family facts
unless it says otherwise.

What the sheet does not say, because the engine owns it:

- how French time words become days ("en 1 mois" is 28 to 31 days);
- the grounding rule: a number or a category word must appear in the cited quote;
- the rule that a stay with documents and no fact is a failure, not a negative;
- evidence, lineage and the audit trail.

## Block 3: `criteria`

### `measures`: which value [added]

A stay often has several values. A measure says which one a criterion reads.

```yaml
measures:
  highest_potassium: {take: highest, of: potassium}
  bmi: {take: lowest, of: bmi, ignore: history, prefer: computed}
  loss_1m: {take: largest_change, of: weight_loss, over_days: [28, 31]}
```

- `take`: `lowest`, `highest`, `earliest`, `latest` or `largest_change`.
- `ignore`: drop these facts, unless that leaves nothing.
- `prefer`: use these facts when at least one exists.
- `over_days`: the period a change must cover. A change over a shorter period
  is a lower bound ("at least 6 %"). A lower bound can confirm a threshold. It
  can never refute one.

### Criterion shapes

| shape | written as | status |
| --- | --- | --- |
| threshold | `bmi < 18.5` | **[base]** |
| band | `17 < bmi < 18.5` | **[base]** |
| presence | `present: sepsis` with an optional `where:` list | **[base]** |
| count | `at_least: 2` and `distinct: drug` | **[base]** |
| time window | `where: [days_from_admission: [-7, 0]]` | **[base]** |
| AND / OR | `all_of: [...]`, `any_of: [...]` | **[base]** |
| per-stratum value | `adult: bmi < 18.5` / `age70: bmi < 22` | **[added]** |
| threshold table | `grip < grip_cut`, with `grip_cut: {M: 26, F: 16}` | **[added]** |
| refutation | `refuted_by: intake_preserved` | **[added]** |
| any measured | `any_measured: [...]`, an OR that skips unmeasured parts | **[added]** |
| fact-to-fact time | `dated_within: {period_of: weight_loss}` | **[added]** |
| judged | `judged: growth_channel` | **[added]** |

A `where:` item is one simple test on one attribute of the fact. All items
must hold. There are no free formulas.

Criteria can be grouped. A group is met when one of its criteria is met.

## Block 4: `answer`

```yaml
answer:
  outputs:
    justified: lab_high AND managed               # [base]
    severity:                                      # [added] first true line wins
      only_if: diagnosis
      first_of:
        - severe: severe
        - moderate: moderate
        - indeterminate: otherwise
  report: [highest_potassium, already_coded]       # [added] values shown beside the answer
```

An output line uses only `AND`, `OR`, `NOT` and names of criteria or groups.

## Marking doubt [added]

Any line can carry `assumed: yes` and a `note:`. It marks a threshold or an
interpretation that the reference text does not state. The read-back lists
every assumed line first, so the reviewer sees them before anything else.

## The read-back

After a run, the engine restates the sheet in plain sentences and shows example
stays. For the hyperkalaemia draft it would read like this:

> I looked at adult stays discharged in 2024.
> A stay is **justified** when its highest potassium is above 5.5 mmol/L and
> the hyperkalaemia was managed.
> **Managed** means one of: a potassium-lowering treatment named in a document
> and not described as usual home treatment; a dialysis act; or at least two
> more potassium results in the 48 hours after the first high one.
> Three lines are assumptions nobody confirmed: the 5.5 threshold, the 48 hours,
> and counting monitoring alone as management.
> 1,204 stays are justified. 310 of them have no E87.5 code. Here are 8 of them
> with their quotes.

The numbers in this example are invented.
