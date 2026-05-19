# Implementation Plan: Happy-Path Response Bodies

**Branch**: `002-response-bodies` | **Date**: 2026-05-19 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-response-bodies/spec.md`

## Summary

Extend the generator so each operation's success response carries a body schema.
The schema is derived by **static inspection** of two sources: the jbuilder view
template the action renders (`app/views/<controller>/<action>.json.jbuilder`)
and literal `render json:` calls in the action body. Each operation's success
response is filed under a conventional status code (200 read/update, 201 create,
204 no-content). The behavior is purely additive — routes, parameters, summaries,
descriptions, and tags are unchanged.

Technical approach: a `JbuilderParser` walks the jbuilder template's Ripper AST
into a response schema; a `RenderExtractor` pulls literal `render json:` hashes
from the action AST. Field **names and structure** are recovered reliably; field
**types** are best-effort — typed when read from a literal, permissive (no
`type`) when read from a jbuilder value expression (FR-013). No controller
action is executed and no HTTP request is made (FR-008).

## Technical Context

**Language/Version**: Ruby 3.1+ (unchanged).

**Primary Dependencies**: `railties`, `yard` — **no new runtime dependency**.
jbuilder templates are read as text and parsed with stdlib `Ripper`; the
`jbuilder` gem itself is not required by this gem. Dev/test unchanged (`rspec`,
`json_schemer`, `rubocop`); the dummy app fixture gains `.json.jbuilder` views.

**Storage**: N/A.

**Testing**: RSpec; the dummy Rails app fixture gains jbuilder view templates
(including a partial) plus a controller action with a literal `render json:`.

**Target Platform**: Ruby 3.1+ / Rails 7.0+ host applications.

**Project Type**: Ruby gem — library API + rake task + CLI (unchanged).

**Performance Goals**: No regression — generation for ~200 routes stays under
5 seconds; jbuilder files are parsed once and cached per template path.

**Constraints**: No execution of host actions or HTTP requests (FR-008);
deterministic output (FR-010); generated document still passes OpenAPI 3.1
validation with response bodies included (FR-009).

**Scale/Scope**: Hundreds of routes; hundreds of jbuilder templates (the
`spacely_web` reference app has ~405).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Status |
|-----------|------------|--------|
| I. Simplicity & YAGNI | No new dependency; jbuilder parsed via stdlib Ripper. Literal evaluation is **extracted from `ParamExtractor` into a shared `LiteralEvaluator`** — removes duplication rather than adding it. Type inference kept best-effort, not a deep AR-introspection engine. | PASS |
| II. Specification Correctness | Response schemas reflect real jbuilder/render source; output validated against the OpenAPI 3.1 meta-schema with bodies included. Unresolvable shapes degrade honestly to a generic response + warning, never a fabricated schema. | PASS |
| III. Test-First Discipline | New components are fixture-driven; the dummy app gains jbuilder views and a literal-render action; tests written before implementation. | PASS |
| IV. Dual Interface Parity | No interface change — the rake task, CLI, and library API all gain response bodies identically through the shared `Generator`. | PASS |
| V. Versioned, Backward-Compatible Output | Output changes for unchanged input (operations gain `responses` content) — a **breaking output change**, released as a MINOR/MAJOR bump with migration notes per the gem's SemVer policy. Output stays deterministic. | PASS (change is versioned) |

No violations — Complexity Tracking section omitted.

*Post-design re-check (after Phase 1): the design adds four focused classes and
one extracted shared module, no new dependency, no new abstraction layer.
Constitution Check still PASSES.*

## Project Structure

### Documentation (this feature)

```text
specs/002-response-bodies/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── response-output.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
lib/rails_openapi_generator/
├── literal_evaluator.rb        # NEW — shared Ripper-literal → Ruby value
│                               #       (extracted from param_extractor.rb)
├── view_locator.rb             # NEW — route/action → jbuilder template path
├── jbuilder_parser.rb          # NEW — parse a .json.jbuilder file → schema
├── render_extractor.rb         # NEW — literal `render json:` in action → schema
├── response_builder.rb         # NEW — status code + body schema → Response
├── param_extractor.rb          # MODIFIED — use shared LiteralEvaluator
├── operation_builder.rb        # MODIFIED — attach responses to the Endpoint
├── document_builder.rb         # MODIFIED — emit responses with content schema
└── generator.rb                # MODIFIED — wire the new pipeline stage

spec/
├── unit/
│   ├── literal_evaluator_spec.rb       # NEW
│   ├── view_locator_spec.rb            # NEW
│   ├── jbuilder_parser_spec.rb         # NEW
│   ├── render_extractor_spec.rb        # NEW
│   └── response_builder_spec.rb        # NEW
├── integration/
│   └── response_bodies_spec.rb         # NEW
└── fixtures/dummy/
    └── app/views/api/                  # NEW jbuilder view fixtures
        ├── users/index.json.jbuilder
        ├── users/show.json.jbuilder
        └── users/_user.json.jbuilder   # a partial
```

**Structure Decision**: Continue the one-class-per-pipeline-stage layout. Four
new classes handle response discovery (`ViewLocator`), the two parse paths
(`JbuilderParser`, `RenderExtractor`), and assembly (`ResponseBuilder`). The
literal-AST evaluation already living inside `ParamExtractor` is promoted to a
shared `LiteralEvaluator` so both the parameter path and the render path use one
implementation (Constitution I). `OperationBuilder`/`DocumentBuilder`/`Generator`
are extended, not restructured.

## Complexity Tracking

No constitution violations — section intentionally empty.
