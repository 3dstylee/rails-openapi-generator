# Implementation Plan: Exclude Endpoints by Source Path

**Branch**: `007-exclude-source-paths` | **Date**: 2026-05-19 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/007-exclude-source-paths/spec.md`

## Summary

Add an `exclude_source_paths` configuration setting — a list of strings
(substring match) and/or regexps. Any route whose resolved controller source
file path matches an entry is omitted from the generated document and recorded
as skipped in the run report. It complements the existing `route_filter` by
filtering on where the controller is defined rather than on the route.

Technical approach: `Configuration` gains the validated `exclude_source_paths`
setting and a `source_excluded?(path)` query. `Generator#build_endpoint`, which
already resolves each route's controller source file, consults that query right
after resolution — skipping the route when its source path matches.

## Technical Context

**Language/Version**: Ruby 3.1+ (unchanged).

**Primary Dependencies**: `railties`, `yard` — **no new dependency**.

**Storage**: N/A.

**Testing**: RSpec; tests configure `exclude_source_paths` to match existing
dummy controllers (no new fixture controller is needed — the match is on the
source file path).

**Target Platform**: Ruby 3.1+ / Rails 7.0+ host applications.

**Performance Goals**: No regression — exclusion is a string/regexp test per
route against an already-resolved path.

**Constraints**: Deterministic output (FR-009); document still passes OpenAPI
3.1 validation; default behavior unchanged when the setting is unset (FR-006).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Status |
|-----------|------------|--------|
| I. Simplicity & YAGNI | No new class, file, or dependency. One validated `Configuration` setting and a query method on it; one guard in `Generator`. The setting is justified by an explicit user need (excluding `vendor/`-style controllers). | PASS |
| II. Specification Correctness | Exclusion is decided from the real resolved source file path; an unresolvable source is left untouched, never guessed. | PASS |
| III. Test-First Discipline | Fixture-driven via the existing dummy app; tests written before implementation. | PASS |
| IV. Dual Interface Parity | No interface change — rake task, CLI, and library API all honor `exclude_source_paths` through the shared `Generator`. | PASS |
| V. Versioned, Backward-Compatible Output | Output changes only when the new setting is configured; the default (empty list) leaves output identical. Released as a MINOR bump (0.7.0) with a CHANGELOG entry. | PASS (change is versioned) |

No violations — Complexity Tracking section omitted.

*Post-design re-check (after Phase 1): the design touches two existing classes,
adds one configuration field plus a query method, and introduces no dependency
or new file. Constitution Check still PASSES.*

## Project Structure

### Documentation (this feature)

```text
specs/007-exclude-source-paths/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── exclusion-output.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
lib/rails_openapi_generator/
├── configuration.rb     # MODIFIED — add exclude_source_paths (validated) and
│                        #   a source_excluded?(path) query
└── generator.rb         # MODIFIED — skip a route whose resolved controller
                         #   source path is excluded

spec/
├── unit/
│   └── configuration_spec.rb            # MODIFIED — exclude_source_paths +
│                                        #   source_excluded? + validation
└── integration/
    └── exclude_source_paths_spec.rb     # NEW
```

**Structure Decision**: No new components. `exclude_source_paths` belongs on
`Configuration` alongside the existing `route_filter`; the matching logic is a
small query method (`source_excluded?`) on `Configuration` so it is unit-tested
through `configuration_spec`. `Generator#build_endpoint` already resolves the
controller source file (`locate_source`), so the exclusion check is a one-line
guard there — skip and record, then drop the route from the document.

## Complexity Tracking

No constitution violations — section intentionally empty.
