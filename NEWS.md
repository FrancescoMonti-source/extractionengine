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

* A payload activation named by `from_channel()` but not referenced by
  `combine_channels()` now runs only for the units the combine qualified. Its
  result for an excluded unit was computed and then discarded; on the LLM path
  that discarded work was one model call per excluded unit. Published values are
  unchanged. Excluded units now report `selection_status` and
  `processing_status` as `not_executed`, and carry no `audit$counts` rows and no
  `audit$lineage` rows for that channel, because a zero count there would claim
  a search that never happened. **Migration:** none for values; read
  `not_executed` if you relied on every task having selection rows for every
  channel. An activation the combine references still defines the gate and runs
  for every unit.

* `channel_status$selection_status` reports `unavailable` for a task whose
  documents are all outside the searchable corpus. This is reachable only
  through a caller-supplied `list(corpus =, docs_index =)` bundle whose index
  names documents the corpus does not contain; such a task used to report
  `no_match`, which claimed the engine had searched documents it cannot read.
  Published values are unchanged, because an unobserved channel and an observed
  absence are both non-members of the hit set. **Migration:** none, unless you
  read `selection_status` for that mismatched-bundle case.

* `audit$lineage` gains a `selector` stage between `window` and `selected`. An
  artifact that matched the channel selector and was then demoted by
  `filter_rows` or `filter_groups` now stops there instead of being left at
  `window`, where it was indistinguishable from an artifact that never matched.
  `audit$counts` is unchanged: the `selector` count it publishes is the same
  number, now read from the lineage rather than from an executor frame.
  **Migration:** none, unless you counted lineage rows by `furthest_stage` and
  assumed filtered rows appeared under `window`.

* `audit$lineage` names its stage column `furthest_stage`, not `stage`.
  Counting lineage rows by `furthest_stage` gives disjoint buckets — a row
  that stopped at the pre-selector is counted there and nowhere else — whereas
  `audit$counts$stage` is cumulative. The two columns deliberately do not share
  a name.

* `audit$execution_manifest` keeps the resolved definition under `spec` and the
  execution facts beside it. `manifest$variable`, `$anchor`, `$combine`,
  `$output`, and `$channels` become `manifest$spec$name`, `$spec$anchor`,
  `$spec$combine`, `$spec$output`, and `$spec$channels`; `$roster` and
  `$executed_at` stay where they were. Inside a channel, `alias` is now `name`
  and `effective_selector` is now `selector`, the names the resolved
  specification uses. The per-channel `source_roles` and `runtime_roles` copies
  are replaced by one `manifest$sources` entry per source the run knows about,
  because a role binding belongs to the source contract rather than to every
  alias that reads it. A field the author left unset is now absent instead of present and `NULL`,
  so `names()` on a manifest channel lists what was configured; reading an unset
  field still returns `NULL`. **Migration:** insert `$spec` before `anchor`,
  `combine`, `output`, and `channels`, read the variable name from
  `$spec$name`, and read role bindings from `manifest$sources`.

* The manifest is now produced by walking the resolved specification instead of
  copying it field by field, so an activation argument can no longer be present
  in the definition and absent from the audit trail. Author code is still
  recorded as text — the data-masked expressions, the `select_event` closure,
  the validated combine expression — and an object that would drag the authoring
  session into the trail, such as an environment, is now an error rather than a
  silent inclusion. The manifest gains `spec$combine$ast`, the expression as the
  engine parsed it, next to `spec$combine$expr`, the string as authored.

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
  from an explicit universe. An incomplete source snapshot now blocks the
  combine only when its expression evaluates `TRUE` with every channel set to
  `FALSE`; otherwise invisible units cannot qualify. Observed hit keys must
  still belong to the enumerable scoped universe, so this does not bypass a
  channel's search boundary or window.

* `audit$execution_manifest` records which data it read and what it ran on. Each
  `manifest$sources` entry gains `class`, `n_rows`, and `digest`, a hash of the
  snapshot the executor read — for a registered source that is the prepared
  frame, so one hash covers the caller's input, the cohort restriction, and the
  normalization together. A tCorpus is hashed over its searchable content and
  not only its metadata. Every supplied entry is recorded, the declared cohort
  included; an entry with an identity but no `roles` was supplied and not read
  by that variable. `manifest$runtime` records the R version, the platform, and
  the version of the engine and of every package it imports, because redsan
  owns normalization, corpustools owns retrieval, and ellmer owns transport:
  the same definition over the same data can answer differently under different
  versions. The identity is computed once per prepared bundle, so a protocol
  pays for it once and every variable of a study records the same snapshot.
  *Measured:* 3.5 ms for a 4.55 MB prepared frame, 0.4% of that run.
