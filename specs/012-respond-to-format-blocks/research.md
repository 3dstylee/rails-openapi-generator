# Phase 0 Research: respond_to Format Blocks

The spec carried no `[NEEDS CLARIFICATION]` markers. Decisions below
were resolved against the existing codebase, the Rails `respond_to`
runtime semantics, and the OpenAPI 3.1 multi-content-type response
model before writing the spec.

## R1. AST shape of `respond_to do |format| ... end`

**Decision**: Detect the literal `respond_to do |fmt| ... end`
pattern: a `:method_add_block` whose call is `respond_to` (an
`:fcall` / `:method_add_arg`) and whose block is a `:do_block` (or
`:brace_block`) with a single block parameter `fmt`. Read the
block parameter's name from the block AST; then walk the block body
for calls of the form `fmt.<symbol>` (a `:call` with receiver
`[:var_ref, [:@ident, fmt, ...]]` and method name `<symbol>`).

Reference AST for `respond_to do |format|; format.html { x };
format.json; end`:

```text
[:method_add_block,
  [:method_add_arg, [:fcall, [:@ident, "respond_to", ...]], []],
  [:do_block,
    [:block_var, [:params, [[:@ident, "format", ...]], nil, nil, nil, nil, nil, nil], false],
    [:bodystmt, [...statements...], nil, nil, nil]]]
```

Each `format.<symbol>` is either:
- a bare `:call` node — `[:call, [:var_ref, [:@ident, "format", ...]], [:@period, ...], [:@ident, "html", ...]]`
- wrapped in `:method_add_block` when the format has a body block.

**Rationale**: Static, Ripper-only, and tightly constrained to the
documented Rails idiom. Capturing the block param's name (rather
than hard-coding `"format"`) handles `respond_to do |fmt|` /
`respond_to do |f|` / etc.

**Alternatives considered**:
- *Hard-code receiver name as `format`*: misses
  `respond_to { |fmt| fmt.json }`. Cheap to do right, so do it right.
- *Detect every `format.X` call regardless of enclosing block*: too
  permissive — a `format.parse` call elsewhere would be mis-detected.
  Rejected.

## R2. Format symbol → content type mapping

**Decision**: Two entries for v1:

| Rails format symbol | OpenAPI content type |
|---------------------|----------------------|
| `:json` | `application/json` |
| `:html` | `text/html` |

Unknown symbols (`:xml`, `:csv`, `:pdf`, `:any`, `:all`, `:js`, etc.)
silently contribute no site. A future feature MAY extend the map.

**Rationale**: These two cover the overwhelming majority of real
`respond_to` usage in Rails APIs. The cost of adding more is low,
but each new format brings its own emission considerations
(`application/xml` schema, `text/csv` schema with no schema, PDF as
`application/octet-stream`); leaving them out keeps the v1 surface
minimal (Principle I). The "silently ignore" rule is consistent
with feature 011's unmapped-status-symbol rule.

**Alternatives considered**:
- *Include `:xml`, `:js`, `:any`*: each introduces an emission
  question. Deferred.
- *Warn on unknown formats*: would add a new warning category for
  marginal value. Rejected.

## R3. Default-view lookup vs. inline render

**Decision**: A `format.<symbol>` call's body resolution follows
this order:
1. If the call has a body block (`format.json do ... end` or
   `format.json { ... }`) and the block contains a render call
   (`render json:`, `render "..."`, `render :symbol`, `render
   template:`, `render action:`, `head`), use the block's render
   (the inline-render path) — feature 010 (json renders) and feature
   011 (template renders) take over.
2. Otherwise (bare `format.X` or empty block or block with no
   render call), emit an unresolved template-render site whose
   `template_name` is the action's default view name
   (`<route.controller>/<route.action>`) and whose `format_hint` is
   the format symbol. The Generator's
   `resolve_template_sites!` pass (feature 011) does the lookup.

**Rationale**: This reuses every existing detection / resolution
mechanism. The format gate is informational — it decides which
content type the contribution lands under; the body comes from the
existing render pipeline.

**Alternatives considered**:
- *Special-case "bare format.json" by looking up the view directly
  in `RenderExtractor`*: requires the extractor to take a dependency
  on `ViewLocator`; rejected (matches feature 011 R3 reasoning).
- *Skip bare `format.X` entirely and only document when an inline
  render exists*: would miss the motivating case (the user's example
  has `format.json` with no block, falling through to the default
  view). Rejected.

## R4. Multi-content-type emission model

**Decision**: Add an optional `content_types: Hash<String, Hash | nil>`
field to `ResponseEntry`. Keys are content-type strings
(`"application/json"`, `"text/html"`); values are the body schema or
`nil` for "known content type, no schema" (e.g. `text/html` has no
schema in today's emission). When `content_types` is set,
`DocumentBuilder` emits one OpenAPI `content` map with all entries;
when `content_types` is nil, the existing per-`kind` emission applies
(byte-identical for non-format-gate entries).

`ResponseBuilder` builds `content_types` only when a status has
sibling sites with distinct `content_type` markers (i.e. one JSON
gate + one HTML gate at the same status). For a status with a single
content type, `content_types` stays nil and the existing `body`
field is used.

**Rationale**: A new opt-in field on the existing struct lets
existing single-content-type emission stay byte-identical (SC-004)
while letting the new multi-content-type case express itself
naturally. Avoids reshaping every `ResponseEntry` to carry a map
(which would touch every existing emission test).

**Alternatives considered**:
- *Always use a `content_types: Hash` on every entry*: cleaner
  conceptually but forces a byte-identity audit on every existing
  emission test for no gain. Rejected.
- *Emit two separate entries (one per content type) under the same
  status key*: illegal OpenAPI — one response key, one entry,
  multiple content types under one `content:`. Rejected.

## R5. Content-type ordering

**Decision**: When multiple content types are emitted under one
status entry, sort by content-type string ascending. For the
common case `(application/json, text/html)`, this yields the deterministic
order `application/json` before `text/html`.

**Rationale**: Determinism (Principle II / feature 010 FR-013).
Content types are short strings; ASCII sort is stable and
unambiguous.

## R6. Same-format collision: gate + existing render

**Decision**: When a `respond_to` JSON gate and a top-level
`render json:` BOTH contribute to the same status, the schemas
collapse via feature 010's existing union rule (identical schemas
dedup; distinct schemas union into `oneOf`). The format gate's
contribution is a "JSON content type" with the resolved view's
schema; the top-level render contributes its own literal schema.

**Rationale**: Consistency with feature 010's same-status rule.
The format-gate site is just another JSON site at that status — it
doesn't need its own collision logic.

**Alternatives considered**:
- *Prefer the format gate over the explicit render at the same
  status*: arbitrary; today's "last-wins / oneOf" rule is already
  consistent for the JSON path. Rejected.

## R7. Kind classification when `respond_to` is the only signal

**Decision**:
- An action whose `respond_to` block only contributes `:html` gates
  (no `:json`, no other renders, no file/redirect) classifies as
  `:html_page` — a single-entry response with `text/html` (today's
  HTML behavior).
- An action whose `respond_to` block contributes any `:json` gate
  (alone or alongside HTML) classifies as `:json` — multi-entry-
  capable, with the multi-content-type emission path active.
- An action whose `respond_to` block contributes only unknown
  formats (e.g. only `format.xml`) is documented as if the
  `respond_to` block were absent. If no other signal contributes,
  the existing fallback rules apply (undeterminable warning fires
  per FR-010).

**Rationale**: Consistency with feature 011 R5 (HTML-only at one
status → `:html_page`). The presence of a JSON gate is the trigger
for multi-content-type emission; an HTML-only action does not need
the multi-content-type path.

## R8. `respond_to` reached through helpers / before_action

**Decision**: The walker already enumerates helper and
`before_action` bodies (feature 010); `respond_to` blocks inside
those bodies are detected the same way. The format gates contribute
to the operation's response set just like top-level renders do.

**Rationale**: Symmetry with feature 010 and 011. No new
machinery; the new detection is just another shape on top of the
existing walker.

**Alternatives considered**:
- *Detect `respond_to` only in the action body*: simpler but
  surprising — a `def show; render_show_or_index; end` that
  delegates to a helper containing the `respond_to` block would
  silently miss the formats. Rejected.

## R9. `respond_to` outside a do-block / yielded format

**Decision**: Only the canonical
`respond_to do |fmt| ... end` (with a block argument and a
do-block) is detected. Variants without an argument
(`respond_to do; ... end` — invalid Rails syntax) and yielded
patterns are out of scope.

**Rationale**: The canonical form is what every real codebase
uses. Generalizing further would multiply edge cases for marginal
gain.

## R10. Determinism with sibling gates

**Decision**: `respond_to` blocks emit format gates in source
order. The per-status grouping in `ResponseBuilder` then
discriminates by `content_type` for the body computation, and
content types are sorted in emission (R5). No new sources of
nondeterminism are introduced.

**Rationale**: Each gate's identity is `(status, content_type)`;
the same source produces the same set, the emission sorts content
types, and the existing schema sort handles unions. Deterministic
by construction.
