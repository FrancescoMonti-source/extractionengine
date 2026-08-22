# Synthetic differential oracle

This developer tool answers one narrow question: did the public observable
result change for the same synthetic inputs? It is not an oracle of clinical
truth and its fixtures carry no patient-derived data.

The snapshot contains only the public `values`, `channel_status`, and `evidence`
views needed by each case. Structured `channel_coverage`, audit internals,
timestamps, latency, and raw model responses are deliberately excluded. Missing
declared envelope columns are fatal; two empty, incompatible frames cannot
compare green.

The cases cover:

- a structured laboratory payload, including one declared task with no payload;
- an `ELTID` combine between two aliases of the same biology source;
- a deterministic fake-LLM extraction with a no-candidate sibling task;
- a metadata-selected document date inside an authored window.

Generate the baseline before changing execution code:

```powershell
Rscript tools/differential-oracle/snapshot.R . outputs/differential-oracle/before.rds
```

After one implementation step, generate and compare the candidate snapshot:

```powershell
Rscript tools/differential-oracle/snapshot.R . outputs/differential-oracle/after.rds
Rscript tools/differential-oracle/compare.R outputs/differential-oracle/before.rds outputs/differential-oracle/after.rds
```

During Phase 1, any difference other than the explicitly planned build error for
the complement-universe guard is a regression. From Phase 2 onward, the diff is
an inventory for human review because some contract changes are intentional.

The `.rds` files remain ignored under `outputs/`. Do not move real-run artifacts
or patient-derived data into this directory.
