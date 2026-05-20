# Feature 018: Helper method argument propagation

**Status**: ready to implement
**Created**: 2026-05-20
**Constitution**: V (versioned backward-compatible output) — bump `0.17.0` → `0.18.0`

## Problem

A render reached only through a receiverless helper method whose
**status** (and sometimes body shape) depends on a method parameter
is silently dropped from the generated OpenAPI document.

Motivating real-world example:

```ruby
def create
  param! :image_url, String, required: true, blank: false
  @project_floormap = ::ProjectFloormaps::UpsertService.call(...)
  render_success(@project.id)
rescue StandardError => e
  render_error(e.message, 422, :unprocessable_entity)
end

def render_error(message, status_code, status)
  render json: { response: {}, message: message, status_code: status_code }, status: status
end
```

The current generator walks `render_error` (feature 010 helper-site
collection) but the render inside it has `status: status` where `status`
is a method parameter. `LiteralEvaluator` returns `UNRESOLVED` for the
parameter reference, and `RenderExtractor#json_site` defensively drops
the entire site when a `status:` option is non-nil but unresolvable.
Result: no 422 entry in the spec; only the happy-path 200/201 appears.

The same gap affects `render_success`-style helpers, `head` / `redirect_to`
wrapped in helpers, and any controller that centralizes error rendering
in a shared method that takes status / payload as parameters.

## User Stories

### US1 (P1) — Positional argument binding

**Given** an action calling a receiverless helper with literal positional
arguments, **when** the helper's body issues a `render` (or `head`,
`redirect_to`, `send_file`) whose option values are references to those
parameters, **then** the generator must substitute the literal argument
values at the call site so the render produces a proper render site.

**Independent test**: fixture controller where `create` calls
`render_error("msg", 422, :unprocessable_entity)` and `render_error`'s
body is `render json: { error: message }, status: status`. The
generated operation must include a 422 entry whose body schema reflects
the literal hash structure.

### US2 (P2) — Recursive (multi-level) propagation

**Given** an action calling helper A with literal args, where A calls
helper B with literal args (possibly including A's bound params),
**when** the generator walks both helpers, **then** B's body must see
A's substituted values; bindings compose through the walk.

**Independent test**: fixture with `def create; outer_helper(:ok); end`,
`def outer_helper(status); inner_helper(status); end`, and
`def inner_helper(status); head status; end`. The operation must
document a 200 entry.

### US3 (P3) — Keyword argument binding

**Given** an action calling a helper with literal keyword arguments,
**when** the helper's body uses those parameters, **then** the kwargs
must bind by name. (Positional args bind by position.)

**Independent test**: fixture with `respond(json: {ok: true}, status: :created)`
calling `def respond(json:, status:); render json: json, status: status; end`.
Operation documents a 201 entry whose body has `ok` as `{type: boolean}`.

## Functional Requirements

- **FR-001**: When the action body contains a receiverless call to a
  resolvable method defined within the app, the generator MUST bind the
  call's literal arguments to the resolved method's parameters by
  position (positional args) and by name (kwarg).
- **FR-002**: An AST node bound to a parameter MUST be substituted for
  every `:var_ref` / `:@ident` reference to that parameter name in the
  helper's body before render extraction.
- **FR-003**: Non-literal argument expressions (method calls, instance
  variables, conditional expressions, etc.) leave the corresponding
  parameter unbound — its references in the body still evaluate to
  `UNRESOLVED` as today.
- **FR-004**: Substitution composes through nested helper calls within
  the substituted body — a helper that itself calls another helper with
  a parameter reference must propagate the outer call's binding into
  the inner call's binding.
- **FR-005**: The walker's recursion is bounded by `max_depth: 5`
  (existing constant). Cycles among helpers terminate when depth is
  exhausted.
- **FR-006**: Multiple call sites of the same helper from one action
  (e.g. both the happy path and a `rescue` clause invoke the same
  helper with different literals) each contribute their own substituted
  body and render sites. No per-location dedup of call sites.
- **FR-007**: Same propagation applies to `before_action`-callback and
  `rescue_from`-handler bodies (each callback's body itself executes
  with no inferred bindings — Rails calls them — but their internal
  helper calls bind as described).
- **FR-008**: Operations whose helpers contain no parameter-dependent
  render sites emit byte-identical responses to `0.17.0`.

## Out of scope (v1)

- Splat (`*args`) and double-splat (`**kwargs`) parameters — these are
  left unbound; any reference to them in the body stays `UNRESOLVED`.
- Default parameter values — when the call omits an optional positional
  or kwarg, the parameter stays unbound (not bound to its default).
- Block-parameter substitution.
- Argument re-assignment inside the helper (`status = compute(status)`)
  — substitution is a static AST swap; if the helper rebinds the param
  to a non-literal expression, the substituted node is still the
  call-site literal. This is conservative-permissive and matches the
  gem's existing posture toward non-literal values.
- Cross-controller resolution: helpers are resolved via the existing
  `MethodResolver`, which only follows methods defined in the
  application's source tree.

## Success Criteria

- **SC-001**: The motivating fixture — an action whose `rescue` clause
  calls `render_error("msg", 422, :unprocessable_entity)` — documents
  both the happy-path entry AND a 422 entry with the literal hash
  schema.
- **SC-002**: A two-level helper chain (action → outer → inner with
  literal forwarding) propagates the binding end-to-end.
- **SC-003**: Operations whose helpers don't use parameter-dependent
  renders emit byte-identical responses to `0.17.0`.
- **SC-004**: Two consecutive runs produce byte-identical output for
  the affected operations (determinism).
