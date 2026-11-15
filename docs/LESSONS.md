# Lessons already paid for

Collected on 15 November 2026 from `redsan-coding` (commit `ba0eeb9`:
`AGENTS.md`, `docs/agents/denut-internals.md`, the ADRs), from this repo's
`DESIGN.md`, and from the fact-layer prototype's note (tag
`archive/fact-layer-prototype-2026-10-04`).

Each line is a rule that a measured failure on real data produced. Any new
design must respect all of them, or say why it does not. The figures are quoted
from those documents. I did not see the runs behind them.

The promises are those of `GOAL.md`.

## Promise 2: every value has its evidence, and nothing is invented

1. **The model points, the code quotes.** The model returns the identifier of a
   fragment it was shown. The code substitutes the exact text. An invented
   quotation becomes impossible, not merely detected.
2. **A number is checked apart from its sentence.** The value must appear in
   the fragment cited for it. A model once reported a BMI of 15 while citing a
   fragment that read 19.5, and every other check passed.
3. **Precision may be dropped, never invented.** 19.74 may be reported as 19.7.
   The reverse is refused.
4. **The model never calculates.** It copies operands. The code does all
   arithmetic and all unit conversion. A wrong answer is then traceable to a
   fragment.
5. **A required field the document does not contain is a machine for
   invention.** Make it optional and give it a deterministic fallback. A
   required date made one model reroute every weight comparison on a nine-stay
   pilot.
6. **A category or a stage is a claim.** Its word must be in the cited text.
   In the prototype this refused 75 of 402 facts, six false diabetic crises
   among them. A model also invented a NYHA stage no document held.
7. **Give the model an honest place for what does not count.** With no box for
   a stroke or a simple infection, it files them in the nearest box that
   counts.
8. **A fragment must stand on its own.** A label and its value are one
   fragment. Split apart, the model cited `IMC :`, five characters and no
   number, and grounding passed.
9. **Resolve a citation by the row it names.** A warehouse element identifier
   is not a row key outside documents. Matching on it returns a different lab
   result without any error.
10. **The code under audit is never evidence for itself.**

## Unknown is not a negative

11. **Silence gives unknown, never "not met".** This applies to the code's own
    arithmetic too.
12. **A lower bound may establish a threshold and may never refute one.**
    Before this rule, 139 of 187 "not met" weight-loss verdicts on one review
    rested on a window too short to say so.
13. **One met criterion settles an OR. An unknown one vetoes nothing.** A grade
    needs evidence and is never a default.
14. **A stay with documents and an empty answer is a failure, not a finding.**
    The clearest case of one cohort came back empty and was counted as
    "nothing found".

## Failing well

15. **Two sizes of failure.** An unreadable answer fails the stay. One bad
    candidate is refused alone, and recorded with its reason, its citation and
    its values. When every flaw was fatal, one model lost seven stays of nine
    to a single field.
16. **Stop when it breaks.** No silent fallback. Every degraded path is
    declared where it lives.
17. **Group failures by cause before counting them.** 48 losses on one pass
    were three unrelated problems. Only two of the 48 said anything about the
    model.
18. **Measure the residue before tightening a check.** Three guards were
    written and withdrawn. Two of them refused five of twelve good phrasings to
    catch one bad citation in about thirty-six stays.

## Promises 3 and 4: reliability is measured and can be measured again

19. **A result names its inputs.** Model and settings, code, rule set and
    documents each have a digest, beside the commit and whether the tree was
    clean. A run from an uncommitted tree is a working result, never evidence.
20. **Compare two runs only after checking they read the same inputs.** Four
    comparisons were once published between runs that had not.
21. **Trust belongs to an identity.** If the model, the rule set or the code
    changes, validation starts again.
22. **Keep sampling what is trusted.** A continuing audit sample is how drift
    is seen.
23. **A second reading may remove trust and never changes the verdict.** It
    answers closed questions, criterion by criterion, and the code derives the
    disagreement. An open "report any concern" refused all six claims of its
    first pilot.
24. **Measure the model's noise before reading a difference.** In the
    prototype, 6 of 64 answers changed between two seeds. Stays sharing a seed
    are not independent draws.
25. **A review is not blind if the reviewer saw the pipeline's answer.** Record
    which kind it was.
26. **A human decision outlives the run it was made on.** It is marked stale
    when the rule set changes, not deleted.
27. **"Implemented" and "run" are different words.** A validation report is
    generated from a saved run and never written by hand. One hand-written
    report described a pass that had never happened.
28. **Recall is not measured anywhere yet.** Nobody has judged stays the
    pipeline did not find. Reordering the records gives a floor under the error
    rate, not a recall.

## Shape of a definition

29. **Split by where to look, not by which reading you want.** One extraction
    per measure. Moderate and severe read the same number at two thresholds.
30. **A concept holds no threshold.**
31. **An interpretation the reference text does not state is versioned and
    visible.** It makes decisions reproducible without claiming clinical truth.
32. **Warehouse vocabularies are messy.** Selection needs labels, exclusions,
    units and plausible ranges, not only codes. Heights are written
    `Taille : 156 m`.
33. **Check incoming data once, at the boundary.** A check repeated downstream
    is duplication.

## The two prohibitions

34. **Patient-derived files never live in the git tree.** Runs write outside
    the repository.
35. **The local model's stability is part of the result.** Anything that works
    only with a stronger model does not meet the goal.
