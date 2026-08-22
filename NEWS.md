# extractionengine (development version)

This cycle rewrote the execution engine while keeping the authoring contract.
Every entry below changes code that already worked, so each one names its
migration.

## Breaking changes to authoring

* `use_channel()` now requires `search_within`, for structured activations as
  well as text. The accepted values are `"PATID"` and `"EVTID"`. The engine no
  longer infers a search boundary from whether a window was declared, which
  means a published value can no longer change with the composition of the
  cohort. **Migration:** add `search_within = "PATID"` or `"EVTID"` to every
  `use_channel()` call. There is no default: an activation that does not
  declare its boundary fails at build time.

* `from_channel()` now requires `ptype`, a zero-length vector prototype, for
  deterministic activations. An all-empty batch and a populated batch used to
  publish different column types. **Migration:** add `ptype = double()`,
  `character()`, and so on. LLM activations must *not* declare it — their
  schema comes from the response — and now error if they do.

* `use_channel()` no longer accepts `model` or `model_params`, and the package
  no longer builds providers or maintains a list of approved models. The caller
  builds one ellmer `Chat` and passes it to `run_variable(chat = )` or
  `run_protocol(chat = )`. A study that needs several models splits its
  variables across several calls on the same cohort and the same source
  snapshot. **Migration:** move the model choice out of the variable definition
  and into the run. The configuration actually used stays recorded in
  `audit$llm_calls`.

* Channel constructors no longer accept or store `native_grain`, and `produces`
  is gone from `inspect()`/`print()` output. **Migration:** delete the argument;
  nothing read it.

* In data-masked expressions — `filter_rows`, `filter_groups`, and the
  `from_channel()` value — a bare name now always means a prepared-source
  column. It used to fall back to the authoring environment, so a misspelled
  column that happened to match an object in the session published that
  object's value, labelled complete, with genuine source rows attached to it as
  its evidence: `mean(NUMRE5)` with `NUMRE5 <- -1` in the session published
  `-1`. The single exception is a name whose nearest ordinary lexical binding
  is a *function*, which is author code rather than data, so
  `vapply(split(NUMRES, ELTID), mean, numeric(1))` and
  ``Reduce(`+`, NUMRES)`` are unchanged. **Migration:** read every external
  value through `.env$`, including option lists
  (`.env$weight_options$remove_missing`). Write `na.rm = TRUE` rather than
  `na.rm = T`: `T` is a redefinable binding, not a literal, so it is now
  reported as a missing column. Active and delayed bindings passed as values
  also require `.env$`; validation never forces them. An export of an attached
  package that nothing has used yet is such a delayed binding, so
  `vapply(NUMRES, kable, numeric(1))` needs `.env$kable`, while calling it as
  `kable(...)` is unaffected.

## Breaking changes to results

* `channel_coverage` is no longer published for structured activations. The
  same executor state used to be translated into `complete` on the membership
  path and `partial` on the `from_channel` path. Operational facts are now rows
  and counts rather than epistemic labels. **Migration:** read
  `channel_status$selection_status` and `audit$counts`. Whole-frame LLM outputs
  keep their existing coverage and review fields until that contract is revised
  separately.

* `audit$internal` has been removed together with its verbatim copies of the
  executor frames. It is replaced by `audit$lineage`, a coordinate-only long
  relation with one row per activation artifact. **Migration:** query
  `audit$lineage` instead. It carries coordinates, never source payload.

* `audit$lineage` names its stage column `furthest_stage`, not `stage`.
  Counting lineage rows by `furthest_stage` gives disjoint buckets — a row
  that stopped at the pre-selector is counted there and nowhere else — whereas
  `audit$counts$stage` is cumulative. The two columns deliberately do not share
  a name.

## Removed exports

* `source_spec()`, `source_roles()`, `validate_source_view()` and
  `edsan_source_specs()` are no longer exported. An author could build a source
  spec successfully and then be told the run required a registered prepared
  EDSAN source; the executor only ever accepted the internal registry.

* `act_channel()` is no longer exported and no longer exists. It had no callers.

## Other changes

* `combine_channels(by = "ELTID")` across two sources is still rejected, but
  the stated reason is now correct: `by` names the key on which the expression
  is evaluated as a single predicate, and two sources can never place a signal
  on the same element. The previous wording claimed that every cross-source
  expression qualified nothing. That is false: with disjoint key spaces,
  `a | b` qualifies their union. A combine at `ELTID` between aliases of the
  *same* source remains legitimate.

* `run_protocol()` resolves every variable specification before preparing
  sources, so a typo in the last variable surfaces before the cohort is
  normalized.

* Prepared sources record the cohort they were prepared for and refuse to be
  reused for a different one.

* Fine-grain combines evaluate the complement over a run-level source roster
  restricted by each participating activation's declared scope and window,
  instead of over the units that happened to produce evidence. Expressions that
  can qualify a unit with no evidence at all — `!a & !b`, `a | !b` — now answer
  from an explicit universe.
