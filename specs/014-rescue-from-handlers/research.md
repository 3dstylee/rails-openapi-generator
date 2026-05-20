# Phase 0 Research: rescue_from Handlers

The spec carried no `[NEEDS CLARIFICATION]` markers. Decisions
below were resolved against the existing codebase (now at v0.13.0),
the Constitution, and Rails' `ActiveSupport::Rescuable` semantics
before writing the spec.

## R1. `rescue_handlers` data shape

**Decision**: `controller_class.rescue_handlers` returns an
`Array` of two-element Arrays. Each inner element is
`[exception_class_string, handler]` where:

- `exception_class_string` is a String like
  `"ActiveRecord::RecordNotFound"`.
- `handler` is either a Symbol (the method name from `with:`) or
  a Proc (from the block form).

Verified by running:

```ruby
c = Class.new(ActionController::API)
c.rescue_from(StandardError, with: :handle)
c.rescue_handlers   # → [["StandardError", :handle]]

c.rescue_from(StandardError) { |e| puts e }
c.rescue_handlers   # → [["StandardError", :handle], ["StandardError", #<Proc:...>]]
```

`rescue_handlers` already merges inherited declarations from parent
classes and from concerns — Rails takes care of that.

**Rationale**: Standard, public Rails API. Same family as
`_process_action_callbacks` (used by `BeforeActionResolver`). The
shape is tiny: two cases (Symbol vs. Proc), one piece of metadata
(the exception name, which we ignore for OpenAPI emission).

## R2. Method-form handler resolution

**Decision**: For a Symbol handler (`with: :record_not_found`),
delegate to the existing `MethodResolver.resolve(controller_class,
method_name)`. The resolver returns a `ResolvedMethod` with the
method's AST node, or `nil` when the method cannot be located in
the application's source (e.g. it lives in a gem). On `nil`, the
handler is silently skipped.

**Rationale**: Reuses the existing method-resolution machinery
used by feature 010's `BeforeActionResolver`. Same broad rescue
behavior, same `app_file?` filter (only walks methods inside the
host application's source).

**Alternatives considered**:
- *Walk all of Rails' internal handlers too*: out of scope — we
  document what the app's own code does. Framework defaults aren't
  generally documentable as response shapes without enumerating
  them, and they may differ across Rails versions.

## R3. Block-form (Proc) handler resolution

**Decision**: For a Proc handler
(`rescue_from FooError do |e| render ... end`), call
`handler.source_location` to get `[file, line]`. Then parse the
file with Ripper and walk the AST for the `:method_add_block` whose
inner call is `rescue_from` and whose `:do_block` / `:brace_block`
starts at the line returned. Capture that block's body AST as the
handler's "method body" equivalent.

If `source_location` is `nil` (an inherited block from a gem, or
a synthetic Proc), the handler is silently skipped.

**Rationale**: Procs created from literal source code in Ruby ≥ 2.7
have a `source_location` (file + line). The resolver uses the same
Ripper parsing already in use by `MethodResolver`. Anchoring on
the line is reliable for the common case (one `rescue_from`
declaration per line). When multiple `rescue_from` blocks share a
line (extremely rare — typically forbidden by linters), the first
matching one is used.

**Alternatives considered**:
- *Skip block-form handlers entirely in v1*: simpler but misses
  a real idiom. The implementation is small (Proc source_location
  + targeted AST search), so it's worth including.
- *Use the `Sourcify` gem*: deprecated and adds a dependency.
  Rejected.

## R4. Resolver caching

**Decision**: One cache per `RescueFromResolver` instance, keyed by
`controller_class`. The first call to `resolve(controller_class)`
walks the rescue_handlers chain and builds a list of resolved
handlers; repeated calls return the same list. The `Generator`
constructs a fresh resolver in `setup_pipeline`, so the cache is
per-generator-run (mirrors `BeforeActionResolver`).

**Rationale**: A controller with 5 actions inheriting 3
`rescue_from` declarations would otherwise walk those 3 handler
bodies 5 times. Caching is a clear win.

**Alternatives considered**:
- *Walk per-action without caching*: simpler but slower. The
  cache is trivial to add — `@cache[controller_class] ||= ...`.

## R5. Source tag on collected sites

**Decision**: Sites collected from rescue handlers carry
`source: :rescue_from`. This joins the existing source tags
(`:action`, `:helper`, `:before_action`) — purely diagnostic;
not emitted to the OpenAPI document.

**Rationale**: Mirrors the existing pattern. Tests can assert
which path produced a given site, and future polish (e.g. an
operation description note "errors are documented via rescue_from
handlers") becomes a one-line addition.

## R6. Aggregation into the operation's response set

**Decision**: The Generator's `collect_extra_sites` (already
combines `:helper` + `:before_action` sites) gains a third
collection: `rescue_from_render_sites(controller_class)`. The
resulting sites flow into the existing `ResponseBuilder.build(...,
extra_sites: ...)` path unchanged. Per-status union and `oneOf`
collapse are inherited from feature 010 FR-004/FR-005.

**Rationale**: Architectural payoff from feature 010's
forward-looking design — the `extra_sites` pipeline was built to
accept exactly this kind of additional render-site source.

**Alternatives considered**:
- *Add a separate "rescue_responses" field on `Endpoint`*:
  parallel pipelines for the same concept. Rejected.

## R7. Inheritance and concern semantics

**Decision**: Rely entirely on Rails' `rescue_handlers` semantics:
declarations on parent classes are merged in; declarations in
included concerns are merged in too. We do NOT separately walk
the ancestor chain — `rescue_handlers` already does that for us.

The order in `rescue_handlers` is registration order: parent
declarations appear before child declarations. When two
declarations resolve to the same status (e.g. both render 404 with
different shapes), feature 010's `oneOf` rule applies.

**Rationale**: Don't re-implement what Rails already does. The
exception of "this controller specifically overrides the parent's
handler" is handled by stacking — both shapes appear in the doc,
which is conservative and truthful (the chain may emit either
depending on which handler runs first at runtime).

**Alternatives considered**:
- *Walk the ancestor chain manually and de-dup by exception
  class*: would let us emit "only the subclass's shape at a
  status, since that's what runs". But it's also fragile — Rails'
  rescue_from resolution can be subtle (rescue_handlers is searched
  in reverse declaration order, with the first match winning, but
  "match" is `is_a?` against the exception class). Implementing
  precise runtime semantics statically is out of scope; the
  conservative "show all shapes" approach is right.

## R8. Re-raising handlers and dynamic statuses

**Decision**: Out of scope per FR-009. A handler whose body
contains `raise OtherError` is walked for renders BEFORE the
raise; whatever it renders before raising counts as documented.
A handler whose `render status: ...` is non-literal (e.g.
`status: error.status_code`) drops the status via the existing
non-literal-status rule (feature 010 R7), and the site
contributes nothing.

**Rationale**: Following the re-raise chain is a stateful
exception-flow analysis — way outside this feature's scope.
The non-literal status drop is the existing behavior, applied
uniformly.

## R9. Determinism

**Decision**: `rescue_handlers` returns in registration order
(deterministic given the host code). The resolver walks them in
that order; sites are tagged `source: :rescue_from`; the
downstream pipeline sorts by status before emission. No new
sources of nondeterminism.

**Rationale**: Constitution-level requirement; inherited from the
existing pipeline.

## R10. SC-004 preservation in the dummy fixture

**Decision**: Add the new `rescue_from` declarations to a NEW
controller hierarchy (`Api::ErrorRescuingController` < ApplicationController),
NOT to `ApplicationController` itself. This isolates the new
fixtures and preserves byte-identity for every existing fixture
controller (which inherits directly from `ApplicationController`).

The concern fixture for US3 (`Api::ErrorRescuingController`'s
included concern) follows the same pattern — confined to the new
hierarchy.

**Rationale**: SC-004 demands byte-identity for operations whose
controllers have no `rescue_from` on the chain. If we declare
rescue_from on `ApplicationController`, every fixture
controller's actions gain new response entries — breaking dozens
of existing integration assertions. Option A (new hierarchy) is
the clean path.

This decision is also captured in the plan's Structure Decision
section.

**Alternatives considered**:
- *Declare on ApplicationController and update every existing
  integration assertion*: violates SC-004 byte-identity guarantee.
  The whole point of SC-004 is to make this change purely
  additive at the per-operation level. Rejected.
