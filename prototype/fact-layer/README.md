# PROTOTYPE: a fact layer with rules on top

Throwaway. Nothing here is part of `extractionengine`, and nothing in `R/` was
changed. It exists to answer one design question, and the answer is in
`NOTE.md`.

## The question

Can a fact layer, with rules on top, express the whole HAS denutrition grid in
about a page, read more simply than today's API, and keep the engine's centre:
grounded citations, the refusal contract and lineage, for text exactly as for
structured sources?

The comparator is `../redsan-coding/analysis/denut_extraction_specs.R`: the
grid written in today's API, nine concepts and nine variables.

## The shape being tested

**A fact** is one thing a record says about one patient, in one row of one
table, whoever produced it: the biology table, the PMSI, a model reading a
letter, a regular expression, or a rule computing from other facts. Every fact
has the same columns. It names its patient and stay, a concept under the
study's own name, a value, the record's date and its own time model, its
qualifiers (negated, hypothetical, historical, family), who asserted it, its
producer and version, and whether it was kept or refused.

**Evidence** is a second table, keyed by fact. A fact read from a source row
cites that row. A fact read from text cites the fragment or the character span
that holds it. A fact computed by a rule cites the facts it was computed from.

**A rule** is R over facts. It never reads a document or a source table. A
measure picks one value per stay, or a lower bound on it. A criterion compares a
measure with a threshold, or asks whether a fact exists. Criteria combine with
`any_of()` and `all_of()`. Every answer is `met`, `not_met` or `unknown`, and it
carries the ids of the facts that decided it.

## Files

| file | what |
| --- | --- |
| `facts.R` | the fact shape and its producers |
| `rules.R` | the rule combinators: the part that would move into the engine |
| `grid.R` | the grid as rules over facts: the page to put beside `denut_extraction_specs.R` |
| `run.R` | builds the facts for the 64 test stays, evaluates the grid, compares |
| `NOTE.md` | the answer |

## Running it

Patient data never enters this tree. `run.R` reads the local corpus and the
luna run, and writes every output under
`tools::R_user_dir("extractionengine", "data")/fact-layer-prototype/`.

```powershell
Start-Process -FilePath "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" `
  -ArgumentList "prototype/fact-layer/run.R" `
  -RedirectStandardOutput run.out -RedirectStandardError run.err -Wait -NoNewWindow
```

Inputs, all local:

- the corpus, `Documents/Datasets/denut/denut_trimmed_v1.2.0_fiche_cora_2026-09-23.rds`;
- the luna run `gpt6-low-779-v120-fiche-cora-aggression-crp-20260929-r2.rds`;
- the bonsai run `bonsai2-27b-budget2048-64-v120-fiche-cora-aggression-catabolism-20261002-s1.rds`,
  for the invented stage only;
- the 64 stay ids in `aggression-b1-batch-ids-20261001.R`;
- `redsancoding` source at `13c92ea`, exported with `git archive` and set in
  `REDSANCODING_SRC`. The installed build of 2026-09-23 predates the run.

No model is called.
