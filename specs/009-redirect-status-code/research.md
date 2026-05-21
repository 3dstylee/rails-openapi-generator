# Phase 0 Research: Redirect Response Status Code

The spec carried no `[NEEDS CLARIFICATION]` markers — every question below was
resolved against the existing codebase, the constitution, and the Rails
`redirect_to` contract before writing the spec. This document records each
decision and the alternatives that were rejected.

## R1. Default status when no `status:` option is given

**Decision**: Treat a bare `redirect_to path` as `302 Found`.

**Rationale**: `302` is the Rails default for `redirect_to` when no `status:`
option is passed. Documenting any other code would diverge from runtime
behavior (violating Principle II). The Rails source has used `302` as the
`redirect_to` default since the framework's inception; it is stable.

**Alternatives considered**:
- *303 See Other for POST, 302 otherwise*: matches REST PRG-pattern guidance,
  but does **not** match what Rails actually emits unless the developer opts
  in with `status: :see_other`. We document what the code does, not what it
  arguably should do.
- *Method convention with body-absence*: documenting `201` (POST default)
  with no body would be even worse than today — it would suppress the warning
  while still showing the wrong status. Rejected.

## R2. Source-statically detected redirect methods

**Decision**: Detect `redirect_to`, `redirect_back`, and
`redirect_back_or_to` as redirect signals; ignore everything else.

**Rationale**: These three are the public Rails API entry points for issuing
a redirect from a controller action. They all return a 3xx response with the
same `status:` semantics, and `RenderExtractor`'s existing `render_calls`
helper already walks the AST for command/method-call sites by name — adding
three more names is a one-line change.

**Alternatives considered**:
- *Just `redirect_to`*: covers the user's reported case but misses
  `redirect_back_or_to`, which is the modern Rails 7+ idiom. The cost of
  including all three is zero.
- *Detect any HTTP 3xx response, including ones set via `response.status=` or
  custom rack-level redirects*: out of scope and unreliable from static
  inspection. The three public Rails methods are sufficient.

## R3. Status-option resolution

**Decision**: Reuse `RenderExtractor::STATUS_CODES` and the existing
`status_code` helper. Accept only 3xx codes as a redirect status. An unknown
symbol or a non-3xx code is treated as "no redirect status" → default `302`
(unknown symbol) or "not a redirect signal" (non-3xx); see R6.

**Rationale**: The Rails-status table is already authoritative and shared
with the explicit-status (Feature 005) code path. Restricting redirect to 3xx
matches the HTTP spec — a `redirect_to … status: :unprocessable_entity` is
a degenerate / mistaken call (Rails will still emit an error response), and
documenting it as a redirect would mislead consumers.

**Alternatives considered**:
- *Accept any explicit status, including 4xx/5xx, as the redirect status*:
  would let one mistaken call corrupt the documented response. Rejected.
- *Hard-code the small set of 3xx codes Rails ships symbols for*: would
  silently demote any literal integer (`status: 308`) that Rails does
  honor. Rejected — range check is correct and simpler.

## R4. Precedence vs. other render signals

**Decision**: Redirect classifies the action **only** when none of the
existing happy-path signals apply — i.e. after JSON / file-download / inline
HTML / view-template lookup, and just above the wrapper-download /
undeterminable fallback.

**Rationale**: `render json:` followed by an early return that also does
`redirect_to` is a misuse rather than a real precedence question — but if it
does occur in source, the action's documented public contract is the JSON
response, not the redirect. The wrapper-download resolver runs last today;
redirect goes immediately above it because a redirect is a direct AST signal
and is cheaper / more certain than the wrapper walk.

**Alternatives considered**:
- *Redirect above everything*: would mis-document an action that does a
  guard-path `redirect_to` followed by a happy-path `render json:`.
  Rejected — backward-incompatible for the common pattern.
- *Redirect alongside `head` (a body-less success)*: appealing symmetrically,
  but `head` is detected as part of the explicit-status mechanism and does
  not own a kind; redirect needs a kind because it changes the
  `response_content` emission (no body, no `application/json` content type).

## R5. Selecting one redirect when more than one is present

**Decision**: Use the **last** happy-path redirect in source order
(consistent with Feature 005's "last happy-path status wins" rule).

**Rationale**: Stays consistent with the existing happy-path render and
explicit-status rules — there is one "documented success path" per action,
and source order is the only stable choice without executing the action.

**Alternatives considered**:
- *First redirect*: arbitrary in the same way; "last" is already the rule
  for the sibling signals so it composes with them.
- *Pick the redirect with the lowest status code*: contrives semantics that
  do not exist at runtime. Rejected.

## R6. Non-3xx `status:` on a redirect call

**Decision**: A `redirect_to … status: :unprocessable_entity` (or any other
non-3xx) is **not** treated as a redirect signal — the action falls back to
the existing classification rules (which today would put it in the JSON /
view / undeterminable path it would otherwise have taken).

**Rationale**: This is consistent with the redirect-status definition in R3
and with FR-009. The call is a degenerate use of `redirect_to`; the safest
action is to ignore it for classification rather than guess the developer's
intent.

**Alternatives considered**:
- *Treat any `redirect_to` as a redirect regardless of status*: emits a
  non-3xx code on an OpenAPI response that claims to be a redirect.
  Rejected — violates Principle II.

## R7. Documenting the `Location` header

**Decision**: Out of scope for v1. The generated redirect response has a
status code and no body; no `headers:` entry is emitted.

**Rationale**: The redirect target in `redirect_to @resource` is dynamic
(`url_for(@resource)`), unknowable from static inspection, and frequently
varies per request. Emitting a placeholder `Location` schema would add noise
without conveying real information. The constitution's Simplicity & YAGNI
principle says: do not add surface area until a concrete need exists. A
future feature can document the header schema (`type: string, format: uri`)
if a real consumer demands it.

**Alternatives considered**:
- *Emit `Location: { schema: { type: string, format: uri } }`*: technically
  correct but adds a header entry to every redirect with no actionable
  value. Deferred.

## R8. Description note on redirect responses

**Decision**: Add a one-line description note (e.g. "_Redirects to another
URL._") via `OperationBuilder#page_note`, mirroring the existing
`_Renders an HTML page._` and `_Sends a file download._` notes.

**Rationale**: The kind is visible in the response status, but a one-line
human-readable note helps consumers reading the rendered document. Cost is
~3 lines and keeps the existing pattern.

**Alternatives considered**:
- *No note*: status code alone is enough machine-side, but the
  human-readable description was the established pattern for `html_page` /
  `file_download` and there is no reason to break the symmetry.

## R9. Vendor extension on the operation

**Decision**: Do **not** add an `x-redirects` vendor extension.

**Rationale**: `x-renders-html` and `x-sends-file` exist because those
endpoints emit a non-JSON content type that consumers using a typed client
would otherwise mis-handle. A redirect's response has no `content` at all,
which is itself the unambiguous signal. Adding `x-redirects` would be
configuration surface with no consumer asking for it (Principle I).

**Alternatives considered**:
- *Add `x-redirects: true`*: harmless but unjustified.
