# Implementation Plan: Implicit Empty Response

**Branch**: `015-implicit-empty-response` | **Date**: 2026-05-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/015-implicit-empty-response/spec.md`

## Summary

Change `ResponseBuilder#undeterminable_response` so that when an
action has zero render sites AND no extras AND the classification is
`:undeterminable`, the returned `Response` is built with
`undeterminable: false` (instead of `!empty_body_path?`). The
documented response shape — one entry at the HTTP-method convention
status with no `content` — is unchanged. The Generator's warning
emit condition is unchanged (still gated on `response.undeterminable?`),
so the practical effect is: the
`"response shape could not be determined"` warning stops firing for
no-signal actions.

Technical approach: one-line behavioral change in
`ResponseBuilder#undeterminable_response`. One spec update in
`spec/integration/response_resilience_spec.rb` to invert the warning
assertion. One regression assertion to confirm the OpenAPI output
is byte-identical for the affected fixture (api/posts#index — the
existing "no signal" fixture). No data-model change, no contract
change, no new dependency.

## Technical Context

**Language/Version**: Ruby 3.1+ (unchanged).

**Primary Dependencies**: unchanged — no new dependency.

**Storage**: N/A.

**Testing**: RSpec; the existing fixture `api/posts#index` already
exercises the "no signal" case (no render, no view, no
respond_to). The test surface is one assertion flip plus a small
regression test to confirm the OpenAPI shape is byte-identical.

**Target Platform**: Ruby 3.1+ / Rails 7.0+ host applications.

**Project Type**: Ruby gem — library API + rake task + CLI
(unchanged).

**Performance Goals**: No measurable impact — one fewer branch
evaluation in `undeterminable_response`.

**Constraints**: OpenAPI document output for the affected case
MUST be byte-identical to `0.14.0` (only the warning channel and
the internal `undeterminable?` predicate change). Operations with
ANY signal (render, view, redirect, file, extras) MUST be
byte-identical to `0.14.0` (FR-004 / FR-005). Document still
passes OpenAPI 3.1 validation (FR-007).

**Scale/Scope**: One file change (`response_builder.rb`), one
test file change (`response_resilience_spec.rb`), plus
README/CHANGELOG. ≤ 10 lines of production code.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Status |
|-----------|------------|--------|
| I. Simplicity & YAGNI | Smallest possible change: one line in `undeterminable_response` flips the `undeterminable` flag for the no-sites branch. No new class, no new field, no new configuration, no new dependency. The dropped `maybe_use_view` from feature 014's fix already removed unused code in the same file — this feature continues the trend. | PASS |
| II. Specification Correctness | The OpenAPI document shape is unchanged. The warning was an internal noise channel that did not survive scaling to real-world apps — silencing it for "no signal" actions reflects the spec's pragmatic reality (Rails returns an implicit empty response for these actions). The change reduces false-positive noise; it doesn't suppress information about real errors. | PASS |
| III. Test-First Discipline | The `response_resilience_spec.rb` flip is the test. The new assertion (no warning for the api/posts#index fixture) is written before the production-code flip. A second integration assertion guards the byte-identity of the OpenAPI output. | PASS |
| IV. Dual Interface Parity | No public interface change — rake task, CLI, and library API all gain the same quieter warning channel through the shared `Generator`. | PASS |
| V. Versioned, Backward-Compatible Output | OpenAPI document output is byte-identical for every existing fixture operation. The change only affects `GenerationReport.warnings` (the noise-suppressing change) and `Response#undeterminable?` (internal). Released as a MINOR bump (0.15.0) with a CHANGELOG entry. | PASS (change is versioned) |

No violations — Complexity Tracking section omitted.

*Post-design re-check (after Phase 1): the change is ≤ 10 lines of
production code, one assertion flip, two doc updates. Smallest
possible feature delivery. Constitution Check still PASSES.*

## Project Structure

### Documentation (this feature)

```text
specs/015-implicit-empty-response/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output (minimal — three decisions)
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

No `data-model.md`, no `contracts/`, no `quickstart.md`. The
change is too small for those artifacts to add value — the
existing fixture and the existing schema already serve as the
"data model" and "contract". Quickstart steps are inline in the
research notes.

### Source Code (repository root)

```text
lib/rails_openapi_generator/
└── response_builder.rb         # MODIFIED — one-line behavioral
                                #   change in
                                #   `undeterminable_response` for
                                #   the `sites.empty?` branch.

spec/
├── integration/
│   └── response_resilience_spec.rb     # MODIFIED — flip the
│                                        #   warning assertion.
                                         #   Add a byte-identity
                                         #   assertion for the
                                         #   OpenAPI shape.
CHANGELOG.md                            # MODIFIED — 0.15.0 entry
README.md                               # MODIFIED — paragraph on
                                        #   the warning's new behavior
lib/rails_openapi_generator/version.rb  # MODIFIED — bump to 0.15.0
```

**Structure Decision**: The smallest possible feature. The
behavioral change is one assignment; the test change is one
assertion. Everything else is documentation.

## Complexity Tracking

No constitution violations — section intentionally empty. This is
the smallest feature in the project's history; the structure is
deliberately minimal.
