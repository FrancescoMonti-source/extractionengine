# What extractionengine is for

Agreed with the owner on 15 November 2026. He said it is aligned and may not be
exhaustive. This page states the "what" only. It says nothing about the "how":
no DSL, no library, no file format. Those may change as the technology moves.
This page should not.

## The goal

Anyone who needs a structured extraction from the hospital's data gets a table
whose reliability they know. That person may be a DIM doctor or a researcher at
the data warehouse.

## The four promises

1. **From a question to a table.** The person describes what they look for.
   They receive one row per patient or per stay, with the variables they asked
   for.
2. **Every value has its evidence.** Beside each answer is the quote or the
   data row it comes from. No evidence, no answer.
3. **Reliability is measured, not promised.** Zero errors does not exist. Each
   extraction states its precision and its recall, the examples it was measured
   on, and the date.
4. **The measure can be redone.** Queries change, and discharge letters change.
   So it must be possible to measure again and see whether quality dropped.

## The two prohibitions

- No patient data leaves the hospital.
- No invented value. What is not found stays "unknown".

## What is not the goal

- Deciding whether a clinical rule is right. That stays with the person who
  asks the question.
- Guaranteeing zero errors.

## What follows from it

- The field is general: PMSI coding and research protocols alike.
- Measuring is part of the product, not a final test.
- The most valuable asset is the set of examples a human has judged. Promises
  3 and 4 are impossible without it, whatever the technology.

## A working definition, to be tested

A **concept** is something found in the record: a lab value, a code, a written
statement. A **rule** is something decided from what was found: it holds a
threshold or a combination. The owner finds this line right and useful, and is
not sure it covers every case.
