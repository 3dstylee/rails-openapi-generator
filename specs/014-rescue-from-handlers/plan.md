# Implementation Plan: rescue_from Handlers

**Branch**: `014-rescue-from-handlers` | **Date**: 2026-05-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/014-rescue-from-handlers/spec.md`

## Summary

Add a `RescueFromResolver` that reads `controller_class.rescue_handlers`
(a public Rails API on every controller — Array of
`[exception_class_string, Symbol|Proc]`), resolves each handler's body
(Symbol → method body via `MethodResolver`; Proc → the proc's
source AST), and returns the list. The Generator's existing
`collect_extra_sites` pipeline (built in feature 010 US3) then walks
each handler body via `RenderExtractor.collect_sites` and adds the
resulting sites to every action's response set with
`source: :rescue_from`. No new field on `RenderSite`. No new emission
path. No new schema rules. Constant resolution in handler bodies
(feature 013) and template-render detection in handler bodies
(feature 011) light up automatically.

Technical approach: the new resolver is the third in a family with
`BeforeActionResolver` (feature 010) — same shape, simpler semantics
(no `only:`/`except:`). The Generator gains one new line to
collect rescue-handler sites alongside helper and before_action
sites. The resolver caches by controller class for the run. Proc-
form handlers are resolved by reading `proc.source_location` (Ruby
6.3+ exposes this for procs created with literal `do ... end` /
`{ ... }` blocks), then parsing the file with Ripper to locate the
specific block AST — same trick used by the existing
`BeforeActionResolver` for callback methods.

## Technical Context

**Language/Version**: Ruby 3.1+ (unchanged).

**Primary Dependencies**: `railties`, `yard` — **no new dependency**.
`rescue_handlers` is part of `ActiveSupport::Rescuable` and shipped
with every Rails controller class.

**Storage**: N/A.

**Testing**: RSpec; the dummy Rails app fixture gains rescue_from
declarations on `ApplicationController` (a method-form handler for
each of three exceptions, mirroring the user's reported pattern)
and one rescue_from in a concern (for US3). A controller in the
fixture adds a per-controller rescue_from (for the override-stacking
case from US1). Integration assertions check every action on every
controller (including untouched ones) gains the inherited entries.

**Target Platform**: Ruby 3.1+ / Rails 7.0+ host applications.

**Project Type**: Ruby gem — library API + rake task + CLI
(unchanged).

**Performance Goals**: One `rescue_handlers` lookup per controller
class per generator run (cached). Each handler's body is walked
once and the resulting sites are cached for reuse across all
actions on the controller. For a 100-action codebase with 5
shared rescue_from handlers, that's 5 body walks (not 500).

**Constraints**: No execution of host actions or handlers (Principle
II); deterministic output (FR-012); operations whose controllers
have no `rescue_from` declarations on the class chain MUST emit
byte-identical output to `0.13.0` (SC-004); document still passes
OpenAPI 3.1 validation.

**Scale/Scope**: Narrow extension — one new class
(`RescueFromResolver`), one new line in the Generator's
`collect_extra_sites`, no changes to `RenderExtractor`,
`ResponseBuilder`, `OperationBuilder`, `DocumentBuilder`, or any
of the schema-mapping path. Touches ~2 files in `lib/`, ~2 unit
specs, 1 integration spec, plus fixture additions.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Status |
|-----------|------------|--------|
| I. Simplicity & YAGNI | One new class with one public method (`resolve(controller_class)` → list of handler sites). Reuses `MethodResolver`, `RenderExtractor.collect_sites`, the existing `RenderSite` struct, and the existing Generator emission pipeline. No new schema rules, no new field on `RenderSite`, no new emission branch. The resolver mirrors `BeforeActionResolver`'s pattern exactly — minimal cognitive overhead. | PASS |
| II. Specification Correctness | The documented 404/403/422 entries reflect the actual response shape every action emits at runtime when the corresponding exception is raised. Re-raising and dynamic-status handlers are explicitly out of scope (FR-009 / Edge Cases). Nothing speculative. | PASS |
| III. Test-First Discipline | Fixture-driven; `ApplicationController` gains rescue_from declarations and handler methods; a concern adds another rescue_from for US3. Unit and integration specs are written before implementation lands, asserting (a) every action gains the inherited entries, (b) handlers in concerns work, (c) block-form handlers work, (d) unresolvable handlers are silently skipped, (e) operations on controllers with no rescue_from are byte-identical (SC-004). | PASS |
| IV. Dual Interface Parity | No public interface change — rake task, CLI, and library API all gain the same coverage through the shared `Generator`. | PASS |
| V. Versioned, Backward-Compatible Output | Operations on controllers whose entire class chain has no `rescue_from` declarations emit byte-identical output to `0.13.0` (SC-004). Operations whose `ApplicationController` (or any ancestor) carries rescue_from gain accurate error-status entries — a strict correctness improvement, released as a MINOR bump (0.14.0) with a CHANGELOG entry. Determinism preserved. | PASS (change is versioned) |

No violations — Complexity Tracking section omitted.

*Post-design re-check (after Phase 1): the design adds one focused
resolver, one line of Generator wiring, and reuses every existing
extraction / emission path. Constitution Check still PASSES.*

## Project Structure

### Documentation (this feature)

```text
specs/014-rescue-from-handlers/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── rescue-from-output.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
lib/rails_openapi_generator/
├── rescue_from_resolver.rb     # NEW — reads
│                               #   controller_class.rescue_handlers,
│                               #   resolves each handler (Symbol →
│                               #   MethodResolver.resolve;
│                               #   Proc → proc.source_location +
│                               #   Ripper to find the do-block AST).
│                               #   Returns an Array of
│                               #   `RescueFromHandler(exception_name,
│                               #   method_node)` for each resolved
│                               #   handler. Caches by controller class.
├── generator.rb                # MODIFIED — `collect_extra_sites` gains
│                               #   a third source: handler bodies from
│                               #   `RescueFromResolver`. Each handler
│                               #   contributes RenderSites with
│                               #   `source: :rescue_from`. The resolver
│                               #   is instantiated in
│                               #   `setup_pipeline`.
└── rails_openapi_generator.rb  # MODIFIED — require the new file.

spec/
├── unit/
│   └── rescue_from_resolver_spec.rb       # NEW — resolver behavior:
│                                          #   method-form, block-form,
│                                          #   inherited from concern,
│                                          #   unresolvable skip,
│                                          #   caching
├── integration/
│   └── rescue_from_handlers_spec.rb       # NEW — end-to-end coverage
│                                          #   for US1/US2/US3 +
│                                          #   regression
└── fixtures/dummy/
    ├── app/controllers/
    │   ├── application_controller.rb      # MODIFIED — declares 3
    │   │                                  #   rescue_from handlers
    │   │                                  #   (record_not_found,
    │   │                                  #   forbidden, bad_request);
    │   │                                  #   includes a concern
    │   │                                  #   (RescueHandlers) for US3
    │   └── concerns/
    │       └── rescue_handlers.rb          # NEW — declares
    │                                       #   `rescue_from
    │                                       #   ParameterMissing,
    │                                       #   with: :bad_request`
    │                                       #   (for US3)
    └── (existing controllers gain
         the inherited entries — no
         per-controller change needed)
```

**Structure Decision**: One new class (`RescueFromResolver`), one
new line in `Generator#collect_extra_sites`. The resolver is
constructed in `setup_pipeline` alongside the other resolvers and
gets cached per generator run. The Generator's existing
`collect_extra_sites` pipeline already aggregates sites with
`source:` markers; adding rescue-handler sites is purely additive.

By the time sites reach `ResponseBuilder`, they're indistinguishable
from before_action sites — the union/dedup rules and constant
resolution apply uniformly.

**Modifying `ApplicationController`**: This is a real concern.
`ApplicationController` is shared across every dummy-app controller
fixture (`UsersController`, `PostsController`, `RedirectsController`,
etc.). Adding `rescue_from` declarations on it means EVERY existing
fixture operation gains 3-4 new response entries — breaking many
existing integration assertions about "expected responses keys".

To preserve SC-004 (byte-identity for operations whose controllers
have NO rescue_from on the chain), we have two options:

**Option A — Add `rescue_from` to a NEW controller's base, not to
`ApplicationController` itself.** Create
`Api::ErrorRescuingController` inheriting from `ApplicationController`
with the rescue_from declarations, plus a new fixture controller
that inherits from `Api::ErrorRescuingController`. Existing fixtures
continue to inherit directly from `ApplicationController` and stay
byte-identical.

**Option B — Add `rescue_from` to `ApplicationController` AND update
the integration assertions for every affected fixture.** Honest about
the new entries, but breaks SC-004 (we can't assert byte-identity
for `0.13.0` outputs).

**Decision**: Option A. This is the SC-004-preserving path; the
new fixtures are isolated to a single controller hierarchy. The
spec's SC-004 is explicit about "operations whose controllers have
no `rescue_from` declarations on the entire class chain emit byte-
identical output". Option A respects that letter and spirit.

## Complexity Tracking

No constitution violations — section intentionally empty. The
resolver is the third in a family with `BeforeActionResolver` and
`MethodResolver` — same shape, same caching pattern, same broad-
rescue posture. Implementation effort is roughly half of feature
010 US3 (no `only:`/`except:` complexity).
