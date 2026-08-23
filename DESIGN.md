# extractionengine design contract

## Product boundary

`extractionengine` executes and audits an operational definition supplied by a
researcher. It does not decide whether that definition is clinically or
scientifically correct.

The responsibility split is:

- `redsan`: EDSAN retrieval, identifiers, table grain, time mechanics, and
  normalized source types;
- researcher-owned code: concepts, selectors, thresholds, windows, value expressions,
  model schemas, and interpretation;
- `extractionengine`: compile the definition, select eligible evidence, execute
  it, and preserve values, operational selection facts, evidence, and provenance;
- `ellmer`: model-provider transport and structured responses.

The package is experimental. Contract clarity takes precedence over backward
compatibility.

## The three authoring layers

The executable definition has three deliberately separate layers:

1. `concept_spec()` locates possible signal rows. A named channel records its
   source and selector; it does not decide which prepared columns a published
   value uses or how it is calculated.
2. `use_channel()` activates one named channel from an explicitly supplied
   concept, or one self-contained inline channel, and decides how candidate rows
   are used.
3. `bin_output(group_by)` or `from_channel(..., group_by, value, ptype)` decides
   the final grain, what is published, and, for a deterministic payload, the
   data-masked value expression and its result type.

`resolve_variable_spec()` is the single compiled representation consumed by
execution, `inspect()`, and provenance. Constructors fail closed: every accepted
argument is validated and used. Reuse is ordinary R code returning a
`variable_spec()`.

## Concepts and activations

`analyte(codes)` only selects lab rows by `TYPEANA`. It does not type a result
lane. `lab_channel()` defaults to the logical source `"biology"` but accepts any
registered source override; source-specific prepared columns come from the
source contract, never from `if (source == ...)` branches.

The built-in biology source uses the canonical `ELTID` exposed by `redsan` as
its source-item coordinate.

`text_channel()` records source and selector only. Relational eligibility belongs
to its activation.

Every entry of `variable_spec(channels =)` is named and must contain
`use_channel(channel = ...)`. The outer name is the activation alias used by
combine expressions, output, inspection, and provenance. A character `channel =`
requires `concept = <concept_spec>` on that activation. An inline channel
definition requires `concept = NULL` because it is already self-contained.
`variable_spec()` has no global concept: different activations may draw from
different reusable concepts, and identical channel names remain unambiguous
inside their explicitly named catalogs. Neither form can refer to another
activation alias. `selector =` is an explicit local replacement.

Operational row, group, and time rules also belong to the activation:

- `search_within = "PATID"` or `"EVTID"` is mandatory and declares the
  source-row relation visible to each task;
- `window = c(from_days, to_days)` filters this activation relative to the
  variable's shared `anchor`; it filters dates inside `search_within` and does
  not infer or narrow that relation;
- `filter_rows` is evaluated independently per task after selector, relational,
  and window selection. It is a data-masked expression over the real
  prepared-source columns, returns one logical per row, treats `NA` as `FALSE`,
  and keeps complete surviving rows;
- `filter_groups`, paired with `use_channel(group_by =)`, runs on those survivors
  in the same data mask and returns exactly one non-missing logical per group
  while retaining all surviving rows of accepted groups. `.data` supports
  programmatic column selection. A bare name is always a prepared-source column,
  so a captured external value is read with `.env$name`; only a name whose
  nearest ordinary lexical binding is a function still resolves from the
  authoring environment. This is an intermediate activation-local grouping
  only; it never sets
  the published grain, which belongs exclusively to the output constructor.

A character `anchor` is the exact date column supplied by the cohort. The engine
copies it to the internal task clock only when a window consumes it; it never
looks for that column in a channel source. `index_event()` is the alternative
pre-channel resolution: it names its own registered source, code selector, and
physical date column independently of the activated channels. Its `select_event`
closure may filter or reorder the matched event rows but cannot synthesize or
alter an `EVTID`/date tuple.

An activation may be used only by `from_channel()`; it need not occur in a
combine expression.

## Output and cardinality

`bin_output(group_by)` publishes observed membership or the result of hit-set
algebra. `from_channel(channel, group_by, value = NULL, ptype = NULL,
filter_by_qualified = NULL)` publishes one activation's payload. `group_by` is
mandatory in both constructors and is the only declaration of final result
grain; there is no default PATID.

For deterministic channels, `value` and a zero-length vector `ptype` are
mandatory. The expression is evaluated once per
final group in a data mask containing its complete, row-aligned prepared-source
rows. It may reference several columns; missing values are not removed
automatically. If no payload row remains, the expression is not evaluated and a
typed missing value is created from `ptype`. Otherwise it must return exactly one
cell and be castable to `ptype`: one atomic scalar or one list cell. Longer or
dimensional results are cardinality errors.
A row carrying `NUMRES`, `STRRES`, both, or neither is valid until the authored
expression uses those columns.

For a `lucene_llm` activation, `value` and `ptype` must be omitted because the
authored response schema already defines the complete structured result frame.

## Relational keys and output grain

The combine and output contracts are self-contained:

- `search_within` in every `use_channel()` controls the source-row relation
  searched before selection or retrieval and is limited to `PATID` or `EVTID`;
- `combine = combine_channels(expr, by)` defines both the boolean expression and
  the identity-spine key where activated signals must coexist;
- `filter_by_qualified` in `from_channel()` chooses the key used to
  `semi_join()` payload rows to the qualifying combine relation;
- `output$group_by` is the final result grain.

`expr` is one boolean expression string over activation aliases using `|`, `&`,
`!`, and parentheses. No separate public hit-set helper constructors are part of
the authoring surface.

`by` names the unit where the whole expression is evaluated as one predicate.
Two sources cannot place signals on the same element, so a cross-source combine
at `by = "ELTID"` has no useful relational grain: conjunction and negation are
degenerate, while disjunction computes the same relation available after
projection to `EVTID` or `PATID`. It is therefore rejected at build time. A
combine at `by = "ELTID"` may still use multiple aliases or selectors resolving
to the same source. If a payload consumes those qualified keys at `ELTID`--through
its final `group_by` or `filter_by_qualified`--that payload must belong to that
same source.

Both `by` and `group_by` are mandatory; neither is inferred from the other. A
combine may be finer than the output (existential projection), equal to it
(direct match), or coarser (explicit broadcast to output units).
At equal or coarser grain, the evaluated universe is the declared output-task
relation. At finer grain, it is an explicit roster built once from all registered
sources supplied to the run, not the union of positive channel hits. Each
referenced activation restricts that roster with the same `search_within` and
window used by execution, and the final universe is the intersection of those
scopes. `ELTID` is additionally restricted to the common source domain. A
pre-retrieved text result cannot provide this source roster, so a fine-grain
combine over such an input fails instead of inventing a complement.
`filter_by_qualified` is admitted and mandatory only for the fine-to-coarse
case. It may then equal `combine$by`, retaining rows of qualifying subunits, or
`output$group_by`, retaining all payload rows of final units with at least one
qualifying subunit. It must be `NULL` without a combine, at equal grain, and for
coarse-to-fine broadcast. The filter never creates an intermediate aggregation.

Payload execution is ordered: `combine by -> filter by qualified -> group by ->
evaluate value`. The value expression is evaluated once per final group on the
aligned raw rows; there is no implicit missing-value removal or lower-grain
aggregation. Public evidence for the payload channel is restricted by the same
qualified-row relation; its complete pre-gate intermediate remains internal
audit data.

LLM responses are compiled as one row per output task. Consequently, an LLM
activation used as a fine-to-coarse payload may set `filter_by_qualified` only
to `output$group_by`; lower-level LLM payload restriction would require per-key
model calls and is outside the current execution contract. An LLM output omits
`value` and publishes the complete structured record.

`search_within = "EVTID"` requires tasks carrying both `PATID` and `EVTID`,
through stay-grain output or an `index_event()`. When stay-grain output searches
within the patient, the target stay remains public `EVTID`; an evidence row's
native stay is kept separately as `source_EVTID`. Text retrieval may collapse a
repeated normalized sentence only within the same native `EVTID`/`ELTID`
identity; identical wording in distinct source units remains distinct relational
evidence. For an LLM activation, task-level normalized-text deduplication is then
applied to the model-candidate view before `max_candidates`, using `snippet_text`
when a pre-retrieved input has no usable `hit_text`; it does not alter the
identity-preserving retrieval view.

A pre-retrieved text fixture must be relationally coherent with real retrieval:
one coverage row per task, only `candidate`, `no_candidate`, or
`no_eligible_document`, and candidate rows exactly for the tasks whose state is
`candidate`.

## LLM contract

An LLM activation receives a native `ellmer::TypeObject` in `response =`.
Authored object and field descriptions contain the variable-specific
instructions. The package supplies a general, overrideable `system_prompt` and
constructs the user message from the target plus numbered excerpts; optional
`user_prompt` is only a prefix for cross-field instructions that do not fit the
schema descriptions.

`rationale` is one activation argument. Omission or `TRUE` adds a required field
with the package's generic evidence-bound description; a non-empty string
overrides that description; `FALSE` or `NULL` omits the field. The engine also
adds `snippet_ids`, constrained to the snippets actually shown, then resolves
those identifiers into the evidence table rather than publishing them as a JSON
field. Authored collisions with engine, grain, or audit fields fail at compile
time. A completed response is valid only if at least one ID resolves. Mixed real
and invented IDs retain the grounded result with a citation warning and discard
invented IDs; zero resolved IDs make the result invalid, typed-missing, and
reviewable while preserving the raw response in audit.

`ellmer::chat_structured()` owns structured generation; the engine does not
construct a manual JSON format. One successful named-list response becomes one
row containing all authored fields and the rationale. No-candidate, model-error,
and invalid-schema paths preserve the same typed frame with missing values plus
separate processing/review state, raw response, evidence, and provenance.

A valid structured response is not implicitly a positive hit. Until the API has
an authored response-to-membership rule, an activation with
`method = "lucene_llm"` cannot be referenced by
`combine = combine_channels(...)`; compilation
fails explicitly. It may still be published by `from_channel()`, including as a
payload gated by a combine over deterministic channels.

Each `lucene_llm` activation owns its response schema and prompt configuration.
Provider, model, and model parameters are execution dependencies: the caller
constructs one Ellmer Chat and passes it to `run_variable(chat =)` or
`run_protocol(chat =)`. That Chat serves every LLM activation in the call, while
execution isolates conversation state with a fresh task clone. A study needing
different models splits its variables across calls over the same cohort and
source snapshot.

## Audit contract

`run_variable()` exposes exactly four top-level components: `values`,
`channel_status`, `evidence`, and `audit`. Published frames use native grain keys
while composite task identifiers remain internal. Deterministic `values` contain
the authored result without a derived `channel_coverage` label: a returned run
completed, while unavailable sources, empty selections, and row counts remain
observable in `channel_status`, evidence, and `audit$counts`. Whole-frame LLM
outputs retain their existing coverage and review fields until that separate
contract is revised.

`channel_status` has one row per output unit and activated channel. Its stable
core identifies output unit, variable, channel, and source. `selection_status`
is exactly `matched`, `no_match`, `unavailable`, or `not_executed`.
`processing_status` is `not_required` for non-LLM channels; for `lucene_llm` it
is exactly `completed`, `not_called`, `invalid`, or `failed`, and both fields
read `not_executed` when the activation did not run for that unit. Selection and
model processing are separate axes and neither label carries a clinical
interpretation.

A payload activation named by `from_channel()` and not referenced by the combine
runs only on the units the gate qualified. Its result for an excluded unit would
be discarded, and on the LLM path that discarded work is one model call per
excluded unit. The skip is published as `not_executed`; the excluded unit gets
no counts and no lineage for that channel, because a zero there would claim a
search that never happened. An activation the combine references defines the
gate and therefore always runs first, over every unit.

Public evidence retains source-specific prepared-row columns and classifies each
row with `evidence_kind = "source_row"`, `"lucene_hit"`, or
`"llm_citation"`. `evidence_ref` is an opaque, non-missing coordinate local to
the executed run and source snapshot, not a globally durable warehouse key. An
LLM citation additionally carries its task-local `snippet_id`. Internal
`source_row_id` and `hit_ref` columns are not published as evidence. A native
evidence `EVTID` is published as
`source_EVTID`; at stay-grain output the target remains `EVTID`, even when the
two values are equal.

`audit$lineage` is the common coordinate-only activation relation. One row
places one `source_row`, searchable `document`, or task-local `snippet` at the
`furthest_stage` it reached: `pre_selector`, `window`, `selector`, `selected`,
`model_input`, `used`, or `cited`. An artifact demoted by `filter_rows` or
`filter_groups` stops at `selector`, so what an activation filter removed stays
visible per artifact instead of only as a difference between two totals. The
column is not called `stage` because
`audit$counts$stage` is cumulative while `furthest_stage` partitions: counting
lineage rows by it gives disjoint buckets that sum to the artifact total. Later
stages imply earlier stages of the same artifact; an artifact is not duplicated
as an event log. Documents and snippets remain
distinct because retrieval is one-to-many. Target grain keys remain distinct
from `source_PATID`/`source_EVTID`/`source_ELTID`; `source_row_ref` resolves
against the caller-owned source snapshot and `artifact_position` records snippet
order.
This relation is authoritative for operational selection, terminal
selection/model-input counts, upstream eligibility/window counts, and fine-grain
combine placement. It also answers whether an activation had a universe to
search at all: a task with no `pre_selector` artifact was never looked at, so
membership publishes `NA` for it rather than an observed `FALSE`. No executor
publishes a per-task state frame; the model call is a separate relation, not a
second reading of the same one. It deliberately does not copy prepared-source
payload.
Pre-retrieved text inputs have no enumerable document universe, so they cannot
publish document-level upstream lineage and begin at their stored snippets.

`audit$counts` is a long table with output-grain keys, `channel`, `stage`,
`unit`, and `n`. The controlled stages are `pre_selector`, `window`, `selector`,
`filtered_selector`, `model_input`, and `output_input`. They count,
respectively, associated structured rows or searchable text documents before
selection, window survivors, selector matches, matches surviving activation
filters, model snippets, and source rows supplied to the terminal value
expression. Stages appear only when separately instrumented, so absence does not
prove an operation did not run. The audit also contains `llm_calls`, one row per
task/channel model invocation actually made. Its independent public fields are
`call_status`, `response_status`, `task_validity`, and `transport_attempts`; the
zero-row table keeps the same schema. The resolved `execution_manifest` is a
configuration snapshot rather than an activity log. Combination runs additionally retain
`overlap`, the task-level channel-membership intersections, and `combine_keys`,
the evaluated key-level relation, inside the audit rather than as ordinary
output tables. Raw executor frames are not returned. The execution manifest has
a compact print method while retaining its complete machine-readable structure.

The execution manifest and `inspect()` record activation name,
`origin_concept`, `origin_channel`, source, and inline/catalog origin,
original and effective selector, row/group filters, activation window,
`search_within`, `combine$by`, `filter_by_qualified`, `output$group_by`, selected
output value expression and `ptype`, and response schema. The manifest holds
that resolved definition under `spec`, obtained by walking the resolved
specification rather than by copying it field by field, so an activation
argument cannot be configured and left unrecorded; author code is rendered as
text and a live environment is refused rather than embedded. Its `sources` entry
records which physical column each source role resolved to, and its `roster`
table records source-qualified unit counts at `PATID`, `EVTID`, and `ELTID`,
including whether each supplied source was enumerable.
Their output view follows the execution order `combine by -> filter by qualified
-> group by -> evaluate value`.

`variable_spec(name =)` is the canonical public identifier. `run_protocol()`
accepts an entirely unnamed list or an entirely named list whose names match
each `spec$name` in order, rejects duplicate canonical names and partial or
discordant naming, and always names returned results from `spec$name`.

## Non-goals

The package does not contain study concepts, infer clinical absence from source
silence, retrieve arbitrary warehouses, define a universal biology schema,
silently repair cardinality or schema violations, or decide scientific meaning.
