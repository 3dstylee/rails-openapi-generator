# Implementation Plan: Explicit Success Status Codes

**Branch**: `005-explicit-status-codes` | **Date**: 2026-05-19 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/005-explicit-status-codes/spec.md`

## Summary

Document each operation's success response under the status code the action
actually sets — read from `head` calls and the `status:` option of `render`
calls — instead of the status guessed from the HTTP method. A `head` response is
documented body-less. When an action sets no explicit happy-path status, the
existing HTTP-method convention (200/201/204) is kept.

Technical approach: `RenderExtractor` already evaluates each `render`'s
`status:` option and already carries a Rails status-symbol → code table. The
feature extends it to also read `head` call statuses, pick the last happy-path
(2xx/3xx) status across all signals, and surface it on `RenderResult`.
`ResponseBuilder` uses that status when present and otherwise falls back to the
method convention. No new class, file, dependency, or configuration.

## Technical Context

**Language/Version**: Ruby 3.1+ (unchanged).

**Primary Dependencies**: `railties`, `yard` — **no new dependency**. Detection
reuses the existing stdlib `Ripper` parse and `RenderExtractor::STATUS_CODES`.

**Storage**: N/A.

**Testing**: RSpec; the dummy Rails app fixture gains actions that set an
explicit status via `head :ok` (on both a POST and a PUT), via
`render … status:`, and via an error-status guard followed by a happy `head`.

**Target Platform**: Ruby 3.1+ / Rails 7.0+ host applications.

**Project Type**: Ruby gem — library API + rake task + CLI (unchanged).

**Performance Goals**: No regression — status extraction is part of the existing
single AST scan of each action.

**Constraints**: No execution of host actions (FR-009); deterministic output
(FR-011); only the documented status code and `head` body absence may change
(FR-010); document still passes OpenAPI 3.1 validation.

**Scale/Scope**: Hundreds of routes; a contained change to two existing classes.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Status |
|-----------|------------|--------|
| I. Simplicity & YAGNI | No new class, file, dependency, or config. The feature extends `RenderExtractor` (which already evaluates `render status:` and owns the status table) and `ResponseBuilder`. The narrow, single-purpose `no_content` flag is generalized into an `explicit_status` — fewer special cases, not more. | PASS |
| II. Specification Correctness | The documented status reflects the status the action actually sets; unmappable/error statuses fall back rather than being guessed. | PASS |
| III. Test-First Discipline | Fixture-driven; the dummy app gains explicit-status actions; tests written before implementation. | PASS |
| IV. Dual Interface Parity | No interface change — rake task, CLI, and library API all gain accurate statuses through the shared `Generator`. | PASS |
| V. Versioned, Backward-Compatible Output | Status codes change for actions that set an explicit status — a correctness fix to output. Released as a MINOR bump (0.5.0) with a CHANGELOG entry. Output stays deterministic. | PASS (change is versioned) |

No violations — Complexity Tracking section omitted.

*Post-design re-check (after Phase 1): the design touches two existing classes,
adds no abstraction, and removes a special case. Constitution Check still
PASSES.*

## Project Structure

### Documentation (this feature)

```text
specs/005-explicit-status-codes/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── status-output.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
lib/rails_openapi_generator/
├── render_extractor.rb     # MODIFIED — RenderResult: replace `no_content`
│                           #   with `explicit_status` + `head`; read head
│                           #   statuses and render `status:` options
└── response_builder.rb     # MODIFIED — use explicit_status; head/204 -> no body

spec/
├── unit/
│   ├── render_extractor_spec.rb     # MODIFIED — head / render status: cases
│   └── response_builder_spec.rb     # MODIFIED — explicit-status / fallback cases
├── integration/
│   └── explicit_status_spec.rb       # NEW
└── fixtures/dummy/
    └── app/controllers/api/statuses_controller.rb   # NEW — explicit-status actions
```

**Structure Decision**: No new components. `RenderResult`'s narrow `no_content`
boolean is replaced by a general `explicit_status` (Integer or nil) plus a
`head` boolean — `head :no_content` becomes just one value of the new field.
`RenderExtractor` gains `head`-status reading alongside the `render status:`
reading it already does; `ResponseBuilder`'s status logic switches from
method-only to explicit-first-with-method-fallback. Everything else in the
pipeline is untouched (FR-010).

## Complexity Tracking

No constitution violations — section intentionally empty.
