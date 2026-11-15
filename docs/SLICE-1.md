# Slice 1: the patient's weight

Status on 15 November 2026: **implemented, never run.** The code passes its
tests on invented documents. It has never met ellmer, a model, or a warehouse
document: the container it was written in has none of the three. The first run
on the owner's PC is the first test, and what it shows is the finding. Lines
marked **[assumed]** are my choices and need the owner's confirmation.

How to run it: `scripts/slice1.R`.

## Why this slice

It is the smallest thing that touches all four promises of `GOAL.md` on real
data. It is a value read from text, so it uses the local model and citations.
It is not a code, so it also covers the research case. The owner can run it on
the denutrition corpus already on his PC.

It is deliberately too small to be useful. Its job is to prove the loop.

## The question

For each stay: which weights, in kg, do the documents write?

The slice builds and measures the **concept** only: every weight written, each
with its value, its role and its date when one is written. The roles are
`current` (measured during this stay), `usual`, `before_illness` and `earlier`.

Which weight counts is not part of the concept. It depends on the question, and
several weights may count: quantifying a weight loss needs at least two. That
choice is a **rule**, and it belongs to each protocol. The owner settled this on
15 November 2026.

One rule is included as an illustration, and it is not measured:
`weight_current_kg` is the `current` weight from the earliest-dated document.

## What goes in

- The stay bundles that `redsan` already builds, documents only.
- A local model served on the PC, as in the prototype.
- Nothing else. No lab table, no PMSI, no other variable.

## What comes out

Four tables, written outside the git tree.

| table | one row per | holds |
| --- | --- | --- |
| `weights` | weight found | the value in kg, as written, its role, the words dating it |
| `evidence` | citation | the quoted fragment and its document, for one weight |
| `refused` | weight refused | the value, the reason, the quoted fragments |
| `stays` | stay | what happened (found, none found, failed), a digest of the documents read, the seed, the model |
| `run` | run | the label, the question's digest, the code commit, clean tree or not, the date |

## How each promise is met

**1. From a question to a table.** Only half in this slice. The definition is
written by hand. No AI writes it yet.

**2. Every value has its evidence.** The model points at a fragment it was
shown. The code quotes it. The number must appear in that fragment, or the
weight is refused and recorded. A value outside 0.3 to 400 kg is refused: the
corpus holds children, so the floor is a very premature newborn. **[assumed]**
A stay with documents and an answer the code cannot read fails. A stay where
nothing was found although a crude text screen sees something like a weight
gets its own status, so it is counted and read.

**3. Reliability is measured.** This is the new part. 80 stays are drawn at
random, with a seed, **before** any run. **[assumed]** The reviewer gets two
files: a page with the documents of each stay, and a sheet. For each stay he
writes **the true answer**: every weight written, with its role, or "none
written". He never sees what the pipeline answered.

An earlier version of this page drew 40 stays where a weight was found and 40
where none was. That was wrong three ways. It needs the run first. It tells
the reviewer what the run answered. And it distorts recall, because the stays
are no longer a fair picture of the corpus.

The code then reports, with the date and the run it applies to:

- precision: of the values found, how many are in the reviewer's answers;
- recall: of the values the reviewer wrote, how many were found;
- how often the role is right when the value is;
- an honest interval. An observed 36 of 40 means "between about 77 % and
  96 %". Small samples give wide intervals, and the report says so.

Each disagreement is listed with its quote, to be read one by one. When the
reviewer finds that the run was right and he missed a weight, he adds it to the
sheet with `basis = adjudicated`. The report counts those answers apart: they
were written after looking at a run, so they are not blind.

**4. The measure can be redone.** The reviewer's answers are the truth about
the documents, not an opinion about one run. They are stored apart from any
run, keyed by stay and by a digest of the documents. So a later run, with
another model or another prompt, is scored against the same answers with no
new human work. If the documents of a stay changed, its answer is marked
stale. A drop between two scores is the drift.

## Also measured: the model's own noise

The same sample is run twice with different seeds, one seed per stay. The
report gives how many answers changed. A difference between two runs means
nothing if it is smaller than this.

## Not in this slice

A concept library, any second variable, structured sources, rules beyond the
one above, an AI writing definitions, and the review app. The first review is
a spreadsheet, as in September.

## Done when

1. The owner runs it on about 80 stays of the denutrition corpus.
2. He fills the review sheet.
3. The report prints lines such as: precision 36 of 40, recall 36 of 45, the
   set of weights changed on 3 of 80 stays, run X, date Y.
4. A second run is scored against the same sheet without new review.

The numbers in line 3 are invented, to show the shape.

## Cost, as a guess

Model time is unknown for a weight-only question. The prototype's full
extraction took a median of about 3 minutes per stay, so 80 stays twice is at
most a working day of machine time, likely much less. The review is 80 stays at
one or two minutes each.

## Open points for the owner

- 80 stays is accepted as the review load for a first measure.
- The bounds 0.3 to 400 kg.
- Temperature. Two runs measure noise only if the model is allowed to vary, so
  the launch script leaves the server's default. If the owner prefers
  temperature 0, noise will read near zero and mean nothing.
