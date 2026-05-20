# Phase 0 Research: Implicit Empty Response

The spec carried no `[NEEDS CLARIFICATION]` markers. Three small
decisions are documented below; no `data-model.md` /
`contracts/` / `quickstart.md` artifacts are produced (the change
is too small to warrant them — see plan).

## R1. Where the change lands

**Decision**: `ResponseBuilder#undeterminable_response` in
`lib/rails_openapi_generator/response_builder.rb`. The relevant
branch today:

```ruby
if sites.empty?
  empty = empty_body_path?(render_result)
  return Response.new(status: status_for(route, render_result), undeterminable: !empty)
end
```

Changes to:

```ruby
if sites.empty?
  return Response.new(status: status_for(route, render_result))
end
```

The `undeterminable:` keyword argument defaults to `false` on
`Response`, so we can drop it. The HTTP-method convention status
is preserved via the unchanged `status_for(...)` call. The
`empty_body_path?` check was previously used to flip `undeterminable`
between `true` and `false` based on whether the action's only
signal was `head` or a 204 — but since this branch already runs
ONLY when `sites.empty?` (no signals at all), the `empty` check
was always false here, so we drop both the variable and the
expression.

**Rationale**: One-line behavioral flip; smaller than the spec
suggested (we can drop the local variable too). The branch's
semantic invariant is now stated directly: "no signals → body-less
response at the convention status, undeterminable: false".

**Alternatives considered**:
- *Keep the `empty` variable for forward-compatibility with a
  future warning that distinguishes head-only from no-signal*:
  speculative; the simpler code is more honest about today's
  semantics. If the future feature wants to bring `empty` back,
  it can.

## R2. Warning emission stays gated on `response.undeterminable?`

**Decision**: The Generator's warning emit condition is unchanged:

```ruby
if response.undeterminable?
  @report.warn("#{route.http_method} #{route.path}: response shape could not be determined")
end
```

Now `undeterminable?` returns `false` for the no-signal case, so
the warning is naturally suppressed without touching the
Generator. The `Response#undeterminable?` predicate remains as
an internal API surface — it now returns `false` for the targeted
case, but future features can re-purpose it (e.g. set it to
`true` for a narrower case like "non-literal render with no
view").

**Rationale**: Localizes the change to `ResponseBuilder`. The
Generator's warning loop is untouched. The predicate's contract
is preserved (it can still be `true` for other cases — though
no production code path sets it today).

**Alternatives considered**:
- *Remove the `undeterminable` field entirely*: would break the
  internal API for callers (none today) and over-commits to "we
  never want this signal". Rejected.
- *Move the warning emit into ResponseBuilder*: the Generator is
  the right place to own warning emission (it has the route
  context). Don't shuffle the concern.

## R3. Test surface

**Decision**: Two changes to
`spec/integration/response_resilience_spec.rb`:

1. The existing assertion that `report.warnings` contains
   `"/api/posts: response shape could not be determined"` is
   **inverted** to assert it does NOT contain that string.
2. A new assertion confirms the OpenAPI document shape is
   byte-identical: the operation's `responses` map has exactly
   one `200` entry with no `content` key — the shape today's
   undeterminable path already produces, but stated explicitly
   so a future regression is caught.

The existing fixture (`api/posts#index`) is the perfect
exercise — it does no render, no view exists, and no extras
contribute. No new fixture needed.

**Rationale**: One existing fixture exercises the case; one
existing spec already touches it. Flipping the assertion and
adding a byte-identity guard is the smallest test surface.

## Quickstart (inline)

```bash
# Before this change:
bundle exec rspec spec/integration/response_resilience_spec.rb
# → 1 example, 0 failures. The spec asserts the warning fires.

# After flipping the spec assertion (test fails):
bundle exec rspec spec/integration/response_resilience_spec.rb
# → 1 example, 1 failure. The warning still fires.

# Apply the one-line production-code fix:
# In lib/rails_openapi_generator/response_builder.rb#undeterminable_response,
# change the empty-sites branch to return without `undeterminable: true`.

bundle exec rspec spec/integration/response_resilience_spec.rb
# → 1 example, 0 failures. The warning no longer fires; the OpenAPI
# output is unchanged.

# Verify byte-identity across the rest of the suite:
bundle exec rspec
# → 470+ examples, 0 failures.

# Lint:
bundle exec rubocop lib spec
# → 0 offenses.
```
