# Phase 1 Data Model: rescue_from Handlers

The feature adds one new class and one new struct, plus one line of
Generator wiring. No existing struct changes shape; no new field
flows through `RenderSite` (the existing `source: :rescue_from` tag
is the only marker, and `source:` is already there).

## New entity: `RescueFromHandler` (lib/rails_openapi_generator/rescue_from_resolver.rb)

The resolved metadata for one `rescue_from` declaration on a
controller class chain.

| Field | Type | Description |
|-------|------|-------------|
| `exception_name` | String | The rescued exception's class name (e.g. `"ActiveRecord::RecordNotFound"`). Informational only — NOT emitted to OpenAPI. Used in tests / debug output. |
| `method_node` | Ripper AST | The handler's method body (for a Symbol handler) or the block's body (for a Proc handler). The Generator walks this via `RenderExtractor.collect_sites`. `nil` when the handler could not be resolved. |

Validation rules:
- A handler whose `method_node` is `nil` is dropped at resolve
  time (the resolver returns only resolvable handlers).
- `exception_name` is non-nil for every returned entry.

## New entity: `RescueFromResolver` (lib/rails_openapi_generator/rescue_from_resolver.rb)

Reads the Rails `rescue_handlers` chain for a controller and
resolves each handler's body to an AST node.

| Field | Type | Description |
|-------|------|-------------|
| `@method_resolver` | `MethodResolver` | Reused for Symbol-form handler bodies. |
| `@cache` | `Hash<Class, Array<RescueFromHandler>>` | Per-instance per-class cache. |

### Public methods

| Method | Returns | Behavior |
|--------|---------|----------|
| `resolve(controller_class)` | `Array<RescueFromHandler>` | Lazily reads `controller_class.rescue_handlers`, resolves each handler's body, and returns the list. Repeated calls return the same list. Returns `[]` when the class is nil or doesn't respond to `rescue_handlers`. Silently catches and ignores all `StandardError`. |

### Private resolution paths

| Handler form | Resolution |
|--------------|------------|
| Symbol (`with: :method_name`) | `method_resolver.resolve(controller_class, method_name)` → `ResolvedMethod` → its `method_node`. nil if unresolvable. |
| Proc (block form) | `handler.source_location` → file + line; parse file via Ripper; locate the `:method_add_block` whose call is `rescue_from` and whose block AST starts at the given line; return that block's body AST. nil if `source_location` is unavailable or the AST can't be located. |

### Lifecycle

- Constructed by `Generator#setup_pipeline` once per generator run.
- Stored as `@rescue_from_resolver` alongside the other resolvers
  (`@walker`, `@wrapper_resolver`, `@before_action_resolver`).
- Cache lives with the instance; replaced on the next pipeline
  setup.

## Generator wiring (lib/rails_openapi_generator/generator.rb)

```text
setup_pipeline:
  @before_action_resolver = BeforeActionResolver.new(method_resolver: @method_resolver)
  @rescue_from_resolver   = RescueFromResolver.new(method_resolver: @method_resolver)   # NEW

collect_extra_sites(route, controller_class, action_source):
  helper_sites   = helper_render_sites(controller_class, action_node)
  callback_sites = before_action_render_sites(controller_class, route.action)
  rescue_sites   = rescue_from_render_sites(controller_class)                            # NEW
  helper_sites + callback_sites + rescue_sites

rescue_from_render_sites(controller_class):                                              # NEW
  handlers = @rescue_from_resolver.resolve(controller_class)
  handlers.flat_map do |handler|
    bodies = @walker.reachable_bodies(controller_class, handler.method_node)
    bodies.flat_map { |body| @render_extractor.collect_sites(body, source: :rescue_from) }
  end
```

The recursion via `@walker.reachable_bodies` means a handler that
calls a helper method (e.g. `def record_not_found; respond_with_error; end`)
walks into the helper too — same logic feature 010 US2/US3 already
applies to `before_action` callbacks.

## Site lifecycle for a rescue_from handler

```text
RescueFromResolver.resolve(controller_class):
  ↓ Read controller_class.rescue_handlers (a Rails-merged Array).
  ↓ For each entry [exception_name, handler]:
    – Symbol handler → MethodResolver.resolve → method_node.
    – Proc handler   → source_location + Ripper-locate → block body AST.
    – Both: build RescueFromHandler(exception_name:, method_node:).
    – Skip silently on any failure.
  ↓ Cache result. Return the list.

Generator#collect_extra_sites:
  ↓ For each RescueFromHandler:
    – @walker.reachable_bodies(controller_class, handler.method_node)
      → walks the handler body PLUS any receiverless helper calls
        from it, recursively bounded by `method_resolution_depth`.
    – For each body, @render_extractor.collect_sites(body, source:
      :rescue_from) → returns RenderSites for `render json:`,
      `head`, `redirect_to`, template renders, etc. — full
      feature 010/011/013 coverage.
  ↓ Returns the flat list of sites.

ResponseBuilder.build(extra_sites:):
  ↓ Sites flow through the existing per-status union/dedup pipeline.
  ↓ A 404 from rescue_from + a 404 from a helper render at the same
    status → collapse per feature 010 FR-004 (identical schemas
    dedup; distinct schemas → oneOf).
```

## Per-operation impact summary

| Controller's class chain | Pre-0.14.0 | After |
|---------------------------|------------|-------|
| No `rescue_from` anywhere on the chain | byte-identical | byte-identical (SC-004) |
| `ApplicationController` has 3 `rescue_from` with method-form handlers, each rendering a distinct status | every operation has the action's own status entries only | every operation gains 3 additional status entries (from the handlers), each with the handler's literal body |
| The same plus a per-controller `rescue_from` for one specific controller | byte-identical for OTHER controllers; (those with their own rescue_from gain it on top of the inherited ones) | the per-controller handler stacks on top of the inherited ones |
| `rescue_from` declared in a concern included into `ApplicationController` | invisible | included via `rescue_handlers` chain; same as if declared directly on `ApplicationController` |
| Block-form rescue_from with a literal-status `render json:` | invisible | gains an entry with the block's body shape |
| Handler whose target method cannot be resolved (in a gem) | invisible | silently skipped; other handlers still contribute |
| Handler that re-raises before rendering | invisible | invisible (no render statically visible before the re-raise) |
| Handler with non-literal status (`status: error.status_code`) | invisible | site dropped per feature 010 R7 (existing behavior) |

## SC-004 preservation strategy

For the dummy app fixture, the new rescue_from declarations live on
a NEW controller hierarchy (`Api::ErrorRescuingController` <
ApplicationController), NOT on `ApplicationController` itself.
This isolates the new fixtures:

- Existing fixture controllers (`UsersController`, `PostsController`,
  etc.) inherit from `ApplicationController` directly → empty
  `rescue_handlers` → byte-identical output (SC-004).
- New fixture controllers inheriting from
  `Api::ErrorRescuingController` → non-empty `rescue_handlers` →
  the new entries appear.

The concern fixture for US3 (`RescueFromConcern`) is included
into `Api::ErrorRescuingController`, NOT into `ApplicationController`
— same isolation strategy.
