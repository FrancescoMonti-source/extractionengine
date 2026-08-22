# Synthetic differential oracle

This developer tool answers one narrow question: did the public observable
result change for the same synthetic inputs? It is not an oracle of clinical
truth and its fixtures carry no patient-derived data.

The snapshot contains only the public `values`, `channel_status`, and `evidence`
views needed by each case. Deterministic `channel_coverage` is not part of that
public contract; audit internals, timestamps, latency, and raw model responses
are also excluded. Missing declared envelope columns are fatal; two empty,
incompatible frames cannot compare green.

The cases cover:

- a structured laboratory payload, including one declared task with no payload;
- an `ELTID` combine between two aliases of the same biology source;
- a deterministic fake-LLM extraction with a no-candidate sibling task;
- a metadata-selected document date inside an authored window;
- three runs that freeze the declared search boundary. The signal sits on one
  stay only. The same stay must answer the same way whether or not its sibling
  is in the cohort, and `search_within` -- not the engine -- must decide whether
  it sees the sibling at all. If the patient-scoped and event-scoped runs ever
  agree, the declaration stopped being load-bearing and defect A is back.

Generate the baseline before changing execution code:

```powershell
Rscript tools/differential-oracle/snapshot.R . outputs/differential-oracle/before.rds
```

After one implementation step, generate and compare the candidate snapshot:

```powershell
Rscript tools/differential-oracle/snapshot.R . outputs/differential-oracle/after.rds
Rscript tools/differential-oracle/compare.R outputs/differential-oracle/before.rds outputs/differential-oracle/after.rds
```

A snapshot pair belongs to one implementation step. Treat every difference as a
regression unless that step explicitly changes the public contract exercised by
the case; inspect the diff before accepting a new baseline.

The `.rds` files remain ignored under `outputs/`. Do not move real-run artifacts
or patient-derived data into this directory.
