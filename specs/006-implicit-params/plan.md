# Implementation Plan: Implicit Params Detection

**Branch**: `006-implicit-params` | **Date**: 2026-05-19 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/006-implicit-params/spec.md`

## Summary

Document request parameters an action reads implicitly off the `params` object —
`params[:key]`, `params.require/permit/fetch/dig` — when they are not declared
via `rails_param`. The action body and, recursively, the receiverless helper
methods it calls are scanned statically; each discovered key becomes an
operation parameter with a permissive ("any") schema. Keys already documented
(via `param!` or a path segment) and Rails-internal keys are skipped.

Technical approach: the recursive action-and-helper traversal already built for
wrapper-download resolution (feature 004) is extracted into a shared
`ControllerMethodWalker`. A new `ImplicitParamScanner` walks those method bodies
for `params` usage and collects key names. `OperationBuilder` merges the
discovered keys into the operation's parameters, deduplicated against existing
ones.

## Technical Context

**Language/Version**: Ruby 3.1+ (unchanged).

**Primary Dependencies**: `railties`, `yard` — **no new dependency**. Detection
reuses stdlib `Ripper`, `MethodResolver`, and the existing parser.

**Storage**: N/A.

**Testing**: RSpec; the dummy Rails app fixture gains actions that read
`params[:key]`, use `require`/`permit`/`fetch`/`dig`, read `params` through a
helper, and read a Rails-internal / path-duplicate key.

**Target Platform**: Ruby 3.1+ / Rails 7.0+ host applications.

**Performance Goals**: No regression — the scan rides the same depth-bounded
helper traversal as feature 004; each resolved file is parsed once and cached.

**Constraints**: No execution of host code (FR-009); deterministic output
(FR-011); additive — existing parameters and other content unchanged (FR-010);
document still passes OpenAPI 3.1 validation.

**Scale/Scope**: Hundreds of routes; the `spacely_web` reference app has ~1,800
`params[:key]` accesses, so this feature adds parameters broadly.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Status |
|-----------|------------|--------|
| I. Simplicity & YAGNI | No new dependency. The recursive helper traversal is **extracted** from `WrapperDownloadResolver` into a shared `ControllerMethodWalker` — `WrapperDownloadResolver` and the new `ImplicitParamScanner` both use it, removing duplication rather than adding it. The depth config is renamed to the now-accurate `method_resolution_depth`. | PASS |
| II. Specification Correctness | Parameters reflect real `params` usage in the action and its helpers; only literal keys are emitted; unresolved helpers and dynamic keys are skipped, never guessed. | PASS |
| III. Test-First Discipline | Fixture-driven; the dummy app gains implicit-params actions; tests written before implementation; feature-004 specs guard the `WrapperDownloadResolver` refactor. | PASS |
| IV. Dual Interface Parity | No interface change — rake task, CLI, and library API all gain implicit parameters through the shared `Generator`. | PASS |
| V. Versioned, Backward-Compatible Output | Operations gain newly discovered parameters — additive; existing parameters unchanged. Released as a MINOR bump (0.6.0) with a CHANGELOG entry, including the `download_resolution_depth` → `method_resolution_depth` config rename. | PASS (change is versioned) |

No violations — Complexity Tracking section omitted.

*Post-design re-check (after Phase 1): the design adds two classes, extracts
one shared class, renames one config key, and adds no dependency. Constitution
Check still PASSES.*

## Project Structure

### Documentation (this feature)

```text
specs/006-implicit-params/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── implicit-params-output.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
lib/rails_openapi_generator/
├── controller_method_walker.rb   # NEW — yields an action body + its resolved
│                                 #   receiverless helper bodies, recursively
│                                 #   (depth-bounded, cycle-guarded)
├── implicit_param_scanner.rb     # NEW — scan method bodies for params[:k] and
│                                 #   require/permit/fetch/dig -> key names
├── wrapper_download_resolver.rb  # MODIFIED — use ControllerMethodWalker
├── configuration.rb              # MODIFIED — rename download_resolution_depth
│                                 #   to method_resolution_depth
├── operation_builder.rb          # MODIFIED — merge implicit params into the
│                                 #   operation's parameters
└── generator.rb                  # MODIFIED — wire ImplicitParamScanner

spec/
├── unit/
│   ├── controller_method_walker_spec.rb   # NEW
│   ├── implicit_param_scanner_spec.rb      # NEW
│   ├── configuration_spec.rb               # MODIFIED — renamed setting
│   └── operation_builder via integration   # (covered by integration spec)
├── integration/
│   └── implicit_params_spec.rb             # NEW
└── fixtures/dummy/
    └── app/controllers/api/
        └── inputs_controller.rb            # NEW — implicit-params actions
```

**Structure Decision**: The recursive "action + receiverless helpers" traversal
is the shared substance of feature 004 and this feature, so it becomes
`ControllerMethodWalker` — one place that owns `MethodResolver` use, the depth
cap, and the cycle guard. `WrapperDownloadResolver` is refactored to consume it
(its feature-004 specs verify the refactor). `ImplicitParamScanner` consumes it
to collect `params` keys. `OperationBuilder` merges those keys as parameters,
deduplicated against path and `param!` parameters and filtered of Rails-internal
keys. The depth configuration, no longer download-specific, is renamed
`method_resolution_depth`.

## Complexity Tracking

No constitution violations — section intentionally empty.
