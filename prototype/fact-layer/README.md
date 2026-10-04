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
| `atomic.R` | a model producer: atomic aggression facts, stages and durations transcribed |
| `rules.R` | the rule combinators: the part that would move into the engine |
| `grid.R` | the grid as rules over facts: the page to put beside `denut_extraction_specs.R` |
| `extract_atomic.R` | asks the local model for atomic facts on the 64 stays, with a checkpoint per stay |
| `every_fact.R` | a model producer of every fact the grid reads, from scratch; R reads its times and amounts and does the arithmetic |
| `extract_every_fact.R` | asks the local model for every fact on the 64 stays, with a checkpoint per stay |
| `compare.R` | the real test: the grid over those facts against DENUT + Bonsai, luna and the review |
| `run.R` | builds the facts for the 64 test stays, evaluates the grid, compares |
| `NOTE.md` | the answer |

## Running it

Patient data never enters this tree. `run.R` reads the local corpus and the
luna run, and writes every output under
`tools::R_user_dir("extractionengine", "data")/fact-layer-prototype/`.

```powershell
New-Item -ItemType Directory -Force $env:TEMP\redsancoding-13c92ea | Out-Null
git -C ..\redsan-coding archive 13c92ea | tar -x -C $env:TEMP\redsancoding-13c92ea
$env:REDSANCODING_SRC = "$env:TEMP\redsancoding-13c92ea"
# Optional, needs llama-server on localhost:8080 (about 2.6 h for the 64; resumes):
Start-Process -FilePath "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" `
  -ArgumentList "prototype/fact-layer/extract_atomic.R", "all" `
  -RedirectStandardOutput extract.out -RedirectStandardError extract.err -Wait -NoNewWindow
Start-Process -FilePath "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" `
  -ArgumentList "prototype/fact-layer/run.R" `
  -RedirectStandardOutput run.out -RedirectStandardError run.err -Wait -NoNewWindow
```

Without the extraction's checkpoint, `run.R` evaluates every variant except the
ones over the model's atomic facts.

The real test runs the same way, also against llama-server, and writes
`every-fact-bonsai-64.rds`, `compare.log` (aggregates), `compare-report.txt`
(quotes, stays local) and `compare-64.rds`:

```powershell
Start-Process -FilePath "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" `
  -ArgumentList "prototype/fact-layer/extract_every_fact.R", "all" `
  -RedirectStandardOutput every.out -RedirectStandardError every.err -Wait -NoNewWindow
Start-Process -FilePath "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" `
  -ArgumentList "prototype/fact-layer/compare.R" `
  -RedirectStandardOutput compare.out -RedirectStandardError compare.err -Wait -NoNewWindow
```

A second seed: pass it after `all` to `extract_every_fact.R`, and alone to
`compare.R`. Seed 2 writes `every-fact-bonsai-64-s2.rds`, `compare-s2.log`,
`compare-s2-report.txt` and `compare-64-s2.rds`, and adds seed 2 against seed 1
to its log. Run `compare.R` for seed 1 first, at the same commit.

It also reads DENUT + Bonsai's closed-list runs of 1 and 2 October
(`bonsai2-27b-budget2048-23-…-closed-20261001-s1.rds` and
`bonsai2-27b-budget2048-41-…-closed-20261002-s1.rds`).

`run.R` stubs `redsan::doceds_onnx_spec()` for the session: the catalog
records the trimmer's identity for audit only, no trimmer artifact is installed
on this machine, and the fragments do not depend on it.

It writes `summary.log` (aggregates only, stays numbered 1-64), `report.txt`
(per stay: facts, quotes, decisions; patient text, stays local) and
`fact-layer-64.rds`.

Inputs, all local:

- the corpus, `Documents/Datasets/denut/denut_trimmed_v1.2.0_fiche_cora_2026-09-23.rds`;
- the luna run `gpt6-low-779-v120-fiche-cora-aggression-crp-20260929-r2.rds`;
- the bonsai run `bonsai2-27b-budget2048-64-v120-fiche-cora-aggression-catabolism-20261002-s1.rds`:
  the same local model judging, beside which its extraction is compared;
- the 64 stay ids in `aggression-b1-batch-ids-20261001.R`;
- `redsancoding` source at `13c92ea`, exported with `git archive` and set in
  `REDSANCODING_SRC`. The installed build of 2026-09-23 predates the run.

The only model called is the local one, by `extract_atomic.R`. No document
leaves the machine.
