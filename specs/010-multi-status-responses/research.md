# Phase 0 Research: Multi-Status Responses

The spec carried no `[NEEDS CLARIFICATION]` markers. The following decisions
were resolved against the existing codebase, the Rails source, and prior
features (002 response bodies, 004 wrapper resolution, 006 implicit params,
009 redirect status) before writing the spec.

## R1. Per-render status assignment

**Decision**: Each `render json:` call's status comes from its own
`status:` option; when absent, the HTTP-method convention applies
(GET/PUT/PATCH → 200, POST → 201, DELETE → 204). Each `head` call's
status comes from its argument (or `head` with no argument → 200). The
"last happy status wins" rule used today by `explicit_status` does NOT
apply to multi-status assembly — every render contributes one entry,
keyed by *its own* status.

**Rationale**: The whole point of the feature is that every render
documents *its own* status. Aggregating by "last wins" is exactly the
behavior we are moving away from. The HTTP-method convention remains the
right default for a status-less render because that is what Rails
actually emits at runtime.

**Alternatives considered**:
- *Treat the explicit-status mechanism (Feature 005) the same way*: the
  `explicit_status` field is computed per action today, not per render —
  the new multi-status model supersedes it for JSON entries. For
  single-render actions, the per-render status is identical to the
  `explicit_status` the action sets, so existing tests pass unchanged.
  `head` and `head + render` actions get the same observable output as
  today (verified in R6 below).

## R2. Union rule for same-status entries

**Decision**: When multiple renders at the same status contribute
schemas, the resulting entry's body is the deterministic union:
- 0 known bodies → no body section.
- 1 known body → that body.
- 2+ distinct known bodies → `{"oneOf": [<schema_a>, <schema_b>, ...]}`
  where the list is sorted by `JSON.generate(schema)` ascending and
  duplicates removed by Hash equality.

A `head` call contributes "no body" — it never adds to `oneOf`, and it
collapses out when at least one render at the same status carries a
known body.

**Rationale**: OpenAPI 3.1's `oneOf` is the standard idiom for "this
response may be any of these shapes". Sorting by canonical JSON keeps
output stable across runs (FR-013); Hash equality is the dedup primitive
the existing schema layer already uses. Folding `head` into "no body"
mirrors the Feature 005 rule that a `head` response is body-less.

**Alternatives considered**:
- *`anyOf` instead of `oneOf`*: `anyOf` admits shapes that mix multiple
  branches at once, which is not what a Rails action returns (one render
  fires, one shape is on the wire). `oneOf` is the precise idiom.
- *Pick the largest schema and discard the others*: throws away
  information. Rejected.
- *Don't dedup at all and emit `oneOf` with duplicates*: violates the
  determinism requirement and produces noisy output.

## R3. `head` + `render json:` at same status

**Decision**: A known render body wins over a `head` at the same status;
the entry has the render's body. Two `head` calls at the same status
collapse into one body-less entry.

**Rationale**: The OpenAPI document's purpose is to describe what
consumers can expect — when one code path returns a known body and the
other returns no body, the documented "type" of the response is the
known shape. (At runtime, the no-body path returns 200 with no body,
which still validates against an `application/json` schema — clients
treat it as "the body may be empty"; the documented schema is the
upper bound.)

**Alternatives considered**:
- *Emit `oneOf: [<render_schema>, {}]`*: `{}` as "any" in OpenAPI 3.1
  is technically valid but tells the consumer nothing, and adds noise to
  the 95% case where the `head` is a degenerate guard. Rejected.
- *Emit two entries (one with body, one body-less)*: OpenAPI does not
  support two responses under one status — we'd have to invent a fake
  content type. Rejected.

## R4. Source list — what counts as "reachable"

**Decision**: Three sources, in this order:
1. The action body itself.
2. Receiverless helper methods called from the action body, recursively
   bounded by `ControllerMethodWalker`'s existing `max_depth`.
3. `before_action` callbacks for the action, walked the same way as
   helpers.

Concern methods come along for free in (2) — a method included from a
concern is a regular instance method on the controller, which
`MethodResolver.resolve(controller_class, name)` already finds via
`Module#instance_method`.

**Rationale**: The walker (Feature 004) is already the trusted "this is
what the action runs" abstraction. Reusing it keeps semantics consistent
with implicit-params and wrapper-download resolution. Including
before_action makes 401/403 guards visible — the #1 source of missing
error documentation.

**Alternatives considered**:
- *Also follow `rescue_from` and exception-implied statuses*: requires
  modeling the exception → handler → status chain (Pundit
  `authorize` → `Pundit::NotAuthorizedError` → handler in
  ApplicationController), and the exception types are app-specific.
  Substantial scope. Deferred to a future feature (FR-009).
- *Restrict to direct calls (no walker)*: misses every guard helper
  the codebase already factors out. Rejected — defeats the feature.

## R5. `before_action` callback chain introspection

**Decision**: Read `controller_class._process_action_callbacks` (a
`CallbackChain` carrying `ActiveSupport::Callbacks::Callback` entries
for `:process_action`). Filter to entries with `kind == :before`. For
each callback, read `instance_variable_get(:@filter)` to get the
method symbol; resolve it via `MethodResolver`. The chain already
flattens inheritance and concern mixins, so this captures parent
controllers and Concerns automatically.

**Rationale**: `_process_action_callbacks` is the canonical Rails
introspection path for the callback chain — every Rails-internals tool
(`abstract_controller-callbacks`, `rails-controller-testing`) uses it.
The underscore prefix signals "internal", but the API has been stable
since Rails 5; this is acceptable framework coupling for a Rails-only
generator. Reading metadata is not "executing the action" (Principle II,
FR-012).

**Alternatives considered**:
- *Parse the controller file for `before_action :name` declarations*:
  works for callbacks declared directly on the controller class, but
  misses inherited and concern-mixed callbacks unless we also parse
  every ancestor. The callback chain already gives us the merged view.
- *Use a public Rails API for the chain*: none exists. The underscore
  is the canonical entry point.

## R6. `only:` / `except:` resolution

**Decision**: Best-effort. Run a second pass over the controller's own
source file (via `YardParser` + `Ripper`), finding every
`before_action :name, only: [...]` / `… except: [...]` command. When
the `only:` / `except:` value is a literal array of symbols, build a
filter for that callback; otherwise the callback is treated as
"applies to every action in the controller" (truthful "may emit").

Inherited callbacks (declared on a parent controller or in a concern)
are NOT cross-checked against the parent's source — their renders
apply to every action in the receiving controller. This is the
documented fallback (FR-008).

**Rationale**: The Rails callback chain stores `only:` / `except:` as
opaque procs (wrapped via `ActiveSupport::Callbacks`), so we cannot
recover them from the chain itself. Re-parsing the controller file is
the cheapest way to recover the literal cases — and those literal
cases are the overwhelming majority of real `only:` / `except:` uses.
Non-literal conditionals (`if: -> { … }`) get the safe fallback.

**Alternatives considered**:
- *Evaluate the proc to discover its truth value*: violates "no
  execution of host actions" (FR-012). Rejected.
- *Treat every callback as applying to every action*: simpler but
  noisier — every `before_action :require_admin, only: [:destroy]`
  would document 403 on five operations. The recovery is cheap enough
  to be worth it.
- *Add a Configuration option to disable `only:` recovery*: YAGNI.

## R7. Status outside the Rails status table

**Decision**: A render whose `status:` symbol is not in
`RenderExtractor::STATUS_CODES` contributes no entry. The same render's
schema does NOT fall back to a different status; the call is silently
dropped from the response set.

**Rationale**: An unknown status symbol almost certainly indicates a
typo or a Rails-version-specific code not yet in the table — emitting
an entry under a guessed status is worse than emitting nothing. The
spec's FR-011 wording confirms: "MUST NOT emit a non-numeric or unknown
status key".

**Alternatives considered**:
- *Document under the HTTP-method convention as a fallback*: hides the
  bug. Rejected.
- *Warn the user*: would add new warning surface area. The same render
  in single-response mode is also silently dropped today; we keep that
  consistent.

## R8. `Response` struct reshape

**Decision**: `Response` becomes a holder for `entries: [Entry]` (with
`Entry = Struct.new(:status, :body, keyword_init: true)`), plus the
existing `kind`, `undeterminable`, `description`, `page_reference`
fields. The old `status` and `body` reader fields go away; callers
read `response.entries.first.status` / `.body` for the single-entry
case (which is most non-JSON callers).

**Rationale**: A list-shaped `Response` is the right model — multi-
entry JSON is the new common case. Keeping single-entry holders as a
list of one keeps the emission code uniform. Removing the old `status`
/ `body` readers (rather than aliasing them) avoids a backwards-compat
shim (Principle I).

**Alternatives considered**:
- *Keep `Response.status` and `Response.body` as primary-entry
  forwarders*: doubles the surface area for the same information and
  encourages callers to ignore the multi-entry shape. Rejected.
- *Make multi-status a separate `MultiResponse` type, parallel to
  `Response`*: doubles the precedence/branching logic in
  `DocumentBuilder` and `OperationBuilder`. Rejected.

## R9. Determinism

**Decision**: Entries within a `Response` are sorted by ascending
numeric status before emission. `oneOf` lists are sorted by canonical
JSON. Render-site collection within one action preserves source order
internally, but the final emission is sort-order-stable so two AST
traversals (or two callback-chain orderings) cannot produce different
documents.

**Rationale**: Determinism is constitution-level (Principle II /
Feature 005's FR-011 and Feature 009's FR-013). The two sort keys
(numeric status, canonical JSON) cover both axes — entries and
schemas — and are cheap.

## R10. The "response shape could not be determined" warning

**Decision**: The warning fires when `response.entries` is empty AND
the operation is not classified as `:redirect` / `:file_download` /
`:html_page`. A status entry whose body is nil (because every render
at that status was non-literal) does NOT fire the warning — the status
is known.

**Rationale**: The original warning's job is to tell the user "I don't
know how to document this endpoint at all" — knowing the status code
is documentation. The PATCH /custom_maisokus case (the motivating
report) goes from 1 entry + warning today to 2 entries + no warning
under the new rule, which matches the spec's success criteria.

**Alternatives considered**:
- *Fire whenever any entry has no body*: keeps noise high (real apps
  have many non-literal renders); contradicts FR-011.
- *Drop the warning entirely*: removes a useful signal for the truly
  un-documentable case. Kept for that case only.
