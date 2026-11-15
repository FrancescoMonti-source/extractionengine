# Slice 1: the patient's weight

Status: a design on one page, for review. No code exists. Lines marked
**[assumed]** are my choices and need the owner's confirmation.

## Why this slice

It is the smallest thing that touches all four promises of `GOAL.md` on real
data. It is a value read from text, so it uses the local model and citations.
It is not a code, so it also covers the research case. The owner can run it on
the denutrition corpus already on his PC.

It is deliberately too small to be useful. Its job is to prove the loop.

## The question

For each stay: which weights, in kg, do the documents write? And which one is
the weight measured during this stay?

- **Found** (a concept): every weight written, with its role. The roles are
  `current` (measured during this stay) and `other` (usual, earlier, before
  the illness).
- **Decided** (one rule): `weight_current_kg` is the `current` weight from the
  earliest-dated document. **[assumed]**

## What goes in

- The stay bundles that `redsan` already builds, documents only.
- A local model served on the PC, as in the prototype.
- Nothing else. No lab table, no PMSI, no other variable.

## What comes out

Four tables, written outside the git tree.

| table | one row per | holds |
| --- | --- | --- |
| `values` | stay | `weight_current_kg`, or "unknown" |
| `evidence` | weight found | the value, its role, the quoted fragment, the document |
| `refused` | weight refused | the value, the reason, the quoted fragment |
| `run` | run | model and settings, code commit, clean tree or not, a digest of the documents read, the date |

## How each promise is met

**1. From a question to a table.** Only half in this slice. The definition is
written by hand. No AI writes it yet.

**2. Every value has its evidence.** The model points at a fragment it was
shown. The code quotes it. The number must appear in that fragment, or the
weight is refused and recorded. A value outside 20 to 300 kg is refused.
**[assumed]** A stay with documents and an answer the code cannot read fails.
A stay with no weight found answers "unknown", never "no weight".

**3. Reliability is measured.** This is the new part. After a run, the code
draws a sample and writes a review sheet:

- 40 stays where a weight was found. **[assumed]**
- 40 stays where none was found. **[assumed]**

For each stay the reviewer writes **the true answer**: the right weight, or
"none written". For found stays the sheet shows the quote. For the others it
shows the documents, and the reviewer does not see what the pipeline answered.

The code then reports, with the date and the run it applies to:

- precision: of the weights found, how many are right;
- recall on the sample: of the weights truly written, how many were found;
- an honest interval. With 40 stays, an observed 36 of 40 means "between about
  77 % and 96 %". Small samples give wide intervals, and the report says so.

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
3. The report prints one line such as: weight, precision 36 of 40, recall 31 of
   40, noise 3 of 80, run X, date Y.
4. A second run is scored against the same sheet without new review.

The numbers in line 3 are invented, to show the shape.

## Cost, as a guess

Model time is unknown for a weight-only question. The prototype's full
extraction took a median of about 3 minutes per stay, so 80 stays twice is at
most a working day of machine time, likely much less. The review is 80 stays at
one or two minutes each.

## Open points for the owner

- Where the new project lives, and its name. I cannot create a repository.
- Whether `earliest current weight` is the right rule, or the lowest, or the
  admission weight only.
- Whether 40 and 40 is an acceptable review load for a first measure.
- Which lessons of `LESSONS.md` this slice must already respect. My reading:
  1 to 5, 8, 11, 14 to 16, 19, 24 to 26, 28 and 34.
