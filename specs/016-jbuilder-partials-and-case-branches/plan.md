# Implementation Plan: jbuilder Partials & case/when Branches

**Branch**: `016-jbuilder-partials-and-case-branches` | **Date**: 2026-05-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/016-jbuilder-partials-and-case-branches/spec.md`

## Summary

Two tightly-scoped improvements to `lib/rails_openapi_generator/jbuilder_parser.rb`:

1. **`json.<key> @collection, partial: "name"` resolution** —
   `add_property` gains a check for a literal `partial:` option in
   the call's argument hash. When present, it delegates to the
   existing `partial_schema(call, seen)` and emits
   `{type: array, items: <partial schema>}` (when a positional
   collection is also present) or `<partial schema>` directly
   (when there's no positional arg). When the block argument is
   present, the block wins (matches jbuilder runtime).

2. **`case` / `when` branch merging** — `visit_statement` adds
   `:case` to the list of conditional shapes; a new helper
   `case_branch_bodies(node)` walks the `:when` chain and the
   optional `:else`, returning each branch's body for the
   existing `each_json_call` to walk. The merge semantics are
   the same as `if` / `elsif` / `else`: all properties from all
   branches are unioned into the same hash, last-wins for
   duplicates.

Both improvements live in one file. No other file changes. No new
class, no new dependency, no new configuration. The existing
`partial_name`, `resolve_partial`, `schema_for_file`, and
`conditional_bodies` helpers are reused as-is.

## Technical Context

**Language/Version**: Ruby 3.1+ (unchanged).

**Primary Dependencies**: `railties`, `yard` — no new dependency.
The parser already uses Ripper directly.

**Storage**: N/A.

**Testing**: RSpec; the dummy app fixture gains one new partial
(`_activity_log.json.jbuilder`) and one new index view that uses
the `json.<key> @c, partial:` form. A separate fixture exercises
the `case`/`when` merge. Unit tests against the parser confirm
each AST shape resolves as expected; integration tests confirm
the generated OpenAPI document picks up the recovered shapes.

**Target Platform**: Ruby 3.1+ / Rails 7.0+ host applications.

**Project Type**: Ruby gem — library API + rake task + CLI (unchanged).

**Performance Goals**: One additional Ripper-AST traversal per
case-block site (linear in case-block size) and one additional
file read per `partial:` reference (cached by `schema_for_file`'s
`@cache` — repeated references to the same partial are cheap).
No measurable impact on real-world apps.

**Constraints**: Cycle-guarded recursion via the existing `seen`
list (FR-001); no controller execution (Constitution Principle II);
deterministic output (FR-012); templates without these shapes emit
byte-identical schemas to `0.15.0` (FR-011); the document
continues to pass OpenAPI 3.1 validation.

**Scale/Scope**: ≤ 20 lines of production code spread across
~5 small modifications in one file. Tests touch ~2 fixtures and
1–2 spec files.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Status |
|-----------|------------|--------|
| I. Simplicity & YAGNI | Both improvements use the existing helpers (`partial_schema`, `conditional_bodies`'s merge semantics). No new class, no new dependency, no new configuration. The `:case` shape is added to one switch; `add_property` gets one new branch. The diff is small in both line count and conceptual surface. | PASS |
| II. Specification Correctness | The recovered schemas reflect real partial / branch contents. The user's reported `today_logs`/`week_logs`/etc. now show the partial's actual shape instead of a permissive `{}`. `case` branches that today emit no properties at all will emit the union of all branch properties — strictly more accurate than the current silent drop. | PASS |
| III. Test-First Discipline | Fixture-driven; new partial + view exercise the `json.X @c, partial:` shape; a separate view exercises `case`/`when`. Unit tests on `JbuilderParser` cover both AST shapes (literal partial, non-literal partial degrading to `{}`, case with else, case without else). Integration tests confirm the generated document picks up the recovered shapes. | PASS |
| IV. Dual Interface Parity | No public interface change. Rake task, CLI, and library API all benefit through the shared parser. | PASS |
| V. Versioned, Backward-Compatible Output | Templates without these specific AST shapes emit byte-identical schemas to `0.15.0`. Templates that have them gain richer documentation — strictly additive. Released as a MINOR bump (0.16.0) with a CHANGELOG entry. Determinism preserved (same partial source → same recovered schema; same case branches → same union). | PASS (change is versioned) |

No violations — Complexity Tracking section omitted.

*Post-design re-check (after Phase 1): the design adds two
narrow code paths in one file, reusing every existing helper.
Constitution Check still PASSES.*

## Project Structure

### Documentation (this feature)

```text
specs/016-jbuilder-partials-and-case-branches/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

No `data-model.md`, `contracts/`, or `quickstart.md` — the feature
is too small to warrant them, mirroring feature 015's minimal
structure. The research file captures the two design decisions
(precedence rule for block-vs-partial, `:case` AST walking).

### Source Code (repository root)

```text
lib/rails_openapi_generator/
└── jbuilder_parser.rb           # MODIFIED:
                                 # 1. `add_property` checks for a
                                 #    literal `partial:` option in
                                 #    the call's args before falling
                                 #    through to value_schema. When
                                 #    present (and no block), emits
                                 #    array/object schema from
                                 #    partial_schema.
                                 # 2. `visit_statement` adds :case
                                 #    to the conditional shapes.
                                 # 3. `conditional_bodies` (or a
                                 #    sibling helper) handles :case
                                 #    by walking the :when chain
                                 #    and optional :else.

spec/
├── unit/
│   └── jbuilder_parser_spec.rb  # MODIFIED — new cases for the
│                                 #   json.<key> partial form, the
│                                 #   block-precedence rule, and
│                                 #   the case/when merge.
├── integration/
│   └── response_bodies_spec.rb  # MODIFIED — extend an existing
│                                 #   spec OR add focused
│                                 #   integration assertions for
│                                 #   the new fixtures.
└── fixtures/dummy/
    └── app/views/api/
        ├── activity_logs/
        │   └── _activity_log.json.jbuilder       # NEW partial
        ├── users/                                # MODIFIED or NEW
        │   └── case_role.json.jbuilder           # NEW — exercises
        │                                          #   case/when merge
        └── (one existing or new template that
             uses `json.<key> @c, partial:`)
```

**Structure Decision**: One production file changes
(`jbuilder_parser.rb`). One new partial fixture and one new view
fixture exercise the two improvements. Existing integration specs
gain assertions for the new shapes.

The version bump and CHANGELOG/README updates round out the
release.

## Complexity Tracking

No constitution violations — section intentionally empty. The
feature reuses every existing helper in the parser; the diff is
a one-file change focused on three narrow AST shapes.
