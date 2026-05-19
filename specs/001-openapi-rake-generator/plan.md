# Implementation Plan: OpenAPI Rake Generator

**Branch**: `001-openapi-rake-generator` | **Date**: 2026-05-19 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-openapi-rake-generator/spec.md`

## Summary

Build a Ruby gem that generates a single OpenAPI 3.1 document describing every
endpoint of a host Rails application. The gem discovers endpoints from the Rails
route set, derives request parameters from the host app's existing `rails_param`
`param!` declarations, and extracts each operation's summary/description from
YARD comments above the controller action. Generation is triggered by a rake
task; an equivalent thin CLI wrapper is also shipped (per Constitution IV).

Technical approach: parameters and comments are obtained by **static source
analysis** of controller files (no controller actions are executed), satisfying
FR-015. Routes are read from Rails' in-memory route set. The document is
assembled as a plain Ruby Hash and serialized to JSON or YAML.

## Technical Context

**Language/Version**: Ruby 3.1+

**Primary Dependencies**: `railties` (route introspection); `yard` (source AST
parsing for both YARD docstrings and `param!` calls). No runtime gem is used to
build the OpenAPI document — it is emitted from a plain Hash via stdlib `json`
and `psych`. Dev/test only: `rspec`, `json_schemer` (validate output against the
OpenAPI 3.1 meta-schema), `rubocop`.

**Storage**: N/A — the only persisted artifact is the generated OpenAPI document
file.

**Testing**: RSpec, exercised against a checked-in dummy Rails application
fixture (`spec/fixtures/dummy`) plus fixture-based unit tests for each component.

**Target Platform**: Ruby 3.1+ with Rails 7.0+ host applications; runs in
development and CI environments.

**Project Type**: Ruby gem — library API + rake task + thin CLI executable.

**Performance Goals**: Generate a complete document for an application of ~200
routes in under 5 seconds on a developer machine.

**Constraints**: MUST NOT execute host controller actions or modify host app
state (FR-015); output MUST be deterministic for unchanged input (SC-008); MUST
pass OpenAPI 3.1 schema validation (FR-005); runs offline.

**Scale/Scope**: A typical Rails application — hundreds of routes, dozens of
controllers.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Status |
|-----------|------------|--------|
| I. Simplicity & YAGNI | Two runtime deps (`railties`, `yard`), both load-bearing. OpenAPI document is a hand-built Hash — no spec-builder framework. No config beyond output path, format, and a route filter (all in FR-012/FR-013). | PASS |
| II. Specification Correctness | Output validated against the OpenAPI 3.1 meta-schema in CI via `json_schemer`; static analysis reads real routes/sources so operations match real app behavior. | PASS |
| III. Test-First Discipline | Every component is fixture-driven; tests written before implementation; dummy Rails app provides realistic inputs. | PASS |
| IV. Dual Interface Parity | Both the rake task and the CLI executable are thin wrappers over `RailsOpenapiGenerator::Generator#generate`; no generation logic in either wrapper. | PASS |
| V. Versioned, Backward-Compatible Output | Gem follows SemVer; document targets a stated OpenAPI version (3.1.0); output is deterministic so diffs are meaningful. | PASS |

No violations — Complexity Tracking section omitted.

*Post-design re-check (after Phase 1): structure and contracts introduce no new
dependencies or abstractions beyond those above. Constitution Check still PASSES.*

## Project Structure

### Documentation (this feature)

```text
specs/001-openapi-rake-generator/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── library-api.md
│   ├── rake-task.md
│   └── cli.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
rails-openapi-generator.gemspec
Rakefile
lib/
├── rails_openapi_generator.rb            # entry point + public API surface
├── rails_openapi_generator/
│   ├── version.rb
│   ├── configuration.rb                  # output path, format, route filter
│   ├── railtie.rb                        # registers the rake task with Rails
│   ├── generator.rb                      # orchestrator: routes → document
│   ├── route_collector.rb                # reads + filters the Rails route set
│   ├── source_locator.rb                 # maps a route to its controller file/method
│   ├── yard_parser.rb                    # parses a controller file's AST once
│   ├── doc_comment_extractor.rb          # summary/description from YARD docstring
│   ├── param_extractor.rb                # param! calls → Parameter records
│   ├── schema_mapper.rb                  # param type/constraints → OpenAPI schema
│   ├── operation_builder.rb              # one route → one OpenAPI operation
│   ├── document_builder.rb               # assembles the full OpenAPI document
│   ├── writer.rb                         # serializes to JSON or YAML
│   ├── report.rb                         # processed/skipped/warning summary
│   └── cli.rb                            # thin CLI wrapper over Generator
└── tasks/
    └── rails_openapi_generator.rake      # rake task wrapper over Generator

exe/
└── rails-openapi-generator               # CLI executable shim

spec/
├── spec_helper.rb
├── unit/                                 # per-component fixture tests
├── integration/                          # end-to-end against the dummy app
└── fixtures/
    └── dummy/                            # minimal Rails app: routes, controllers
```

**Structure Decision**: Standard single-gem layout. Runtime code lives under
`lib/rails_openapi_generator/`, one class per pipeline stage so each is
independently testable (Constitution III). The rake task (`lib/tasks/…rake`) and
the CLI (`exe/…`) are both wrappers that build a `Configuration` and call
`Generator#generate` — no logic is duplicated between them (Constitution IV).
Tests are split into `unit/` (component-level) and `integration/` (whole
pipeline against `spec/fixtures/dummy`).

## Complexity Tracking

No constitution violations — section intentionally empty.
