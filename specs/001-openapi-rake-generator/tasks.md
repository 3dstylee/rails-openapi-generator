---
description: "Task list for OpenAPI Rake Generator implementation"
---

# Tasks: OpenAPI Rake Generator

**Input**: Design documents from `/specs/001-openapi-rake-generator/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Test tasks ARE included — Constitution Principle III (Test-First
Discipline) mandates every behavior change be covered by an automated test
written before/alongside implementation. Tests must fail before the
implementing code exists.

**Organization**: Tasks are grouped by user story (US1 P1, US2 P2, US3 P3) so
each story is an independently testable increment.

## Path Conventions

Single Ruby gem at repository root: runtime code in `lib/rails_openapi_generator/`,
rake task in `lib/tasks/`, CLI in `exe/`, tests in `spec/` with a dummy Rails
app under `spec/fixtures/dummy/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Gem skeleton and tooling

- [X] T001 Create gem directory structure (`lib/rails_openapi_generator/`, `lib/tasks/`, `exe/`, `spec/unit/`, `spec/integration/`, `spec/fixtures/`) per plan.md
- [X] T002 Create `rails-openapi-generator.gemspec` declaring runtime deps `railties` and `yard`, dev deps `rspec`, `json_schemer`, `rubocop`, and Ruby `>= 3.1`
- [X] T003 Create `lib/rails_openapi_generator/version.rb` with `VERSION` constant and `lib/rails_openapi_generator.rb` entry point requiring submodules
- [X] T004 [P] Create `Rakefile` wiring RSpec and RuboCop default tasks
- [X] T005 [P] Configure RuboCop in `.rubocop.yml` for the gem
- [X] T006 [P] Configure RSpec in `spec/spec_helper.rb` and `.rspec`
- [X] T007 Create dummy Rails app fixture in `spec/fixtures/dummy/` with `config/environment.rb`, a routes file, and controllers using `rails_param` `param!` calls and YARD comments (covers GET/POST, path params, an action with no params, an action with no comment, a route with no backing action)
- [X] T008 [P] Add a JSON-schema validation helper in `spec/support/openapi_schema.rb` that validates a document against the bundled OpenAPI 3.1 meta-schema via `json_schemer`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core types and orchestration skeleton that every user story builds on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T009 [P] Implement error classes (`ConfigurationError`) in `lib/rails_openapi_generator/errors.rb`
- [X] T010 [P] [Test] Unit spec for `Configuration` defaults, format inference, and validation in `spec/unit/configuration_spec.rb`
- [X] T011 Implement `Configuration` (output_path, format, route_filter, title, api_version; validation raising `ConfigurationError`) in `lib/rails_openapi_generator/configuration.rb` and `RailsOpenapiGenerator.configure`/`.configuration` in `lib/rails_openapi_generator.rb`
- [X] T012 [P] Implement the `Route` value object (http_method, path, controller, action, path_params, external) in `lib/rails_openapi_generator/route.rb`
- [X] T013 [P] [Test] Unit spec for `GenerationReport` accessors and `success?` in `spec/unit/report_spec.rb`
- [X] T014 Implement `GenerationReport` (processed_count, skipped, warnings, output_path, success?) in `lib/rails_openapi_generator/report.rb`
- [X] T015 Implement `Generator` orchestrator skeleton (`#new`, `#generate`, `#document`) in `lib/rails_openapi_generator/generator.rb` — pipeline stages stubbed, returns an empty valid document
- [X] T016 Implement `Railtie` registering the rake task load path in `lib/rails_openapi_generator/railtie.rb`

**Checkpoint**: Core types compile and `Generator#generate` returns an empty valid OpenAPI document

---

## Phase 3: User Story 1 - Generate an OpenAPI document for all endpoints (Priority: P1) 🎯 MVP

**Goal**: Running the rake task (or CLI) produces one valid OpenAPI 3.1 document with one operation per discovered route.

**Independent Test**: Run generation against `spec/fixtures/dummy` and confirm the output contains an operation for every route with correct method/path and passes OpenAPI 3.1 schema validation.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T017 [P] [US1] Unit spec for `RouteCollector` (discovers routes, applies `route_filter`, flags external routes) in `spec/unit/route_collector_spec.rb`
- [X] T018 [P] [US1] Unit spec for `Writer` (JSON and YAML serialization, deterministic key order) in `spec/unit/writer_spec.rb`
- [X] T019 [P] [US1] Unit spec for `DocumentBuilder` (openapi/info/paths assembly, sorted output) in `spec/unit/document_builder_spec.rb`
- [X] T020 [P] [US1] Integration spec: generate against the dummy app, assert one operation per route, correct method/path, empty-app case, and OpenAPI 3.1 schema validity in `spec/integration/generate_all_endpoints_spec.rb`

### Implementation for User Story 1

- [X] T021 [P] [US1] Implement `RouteCollector` reading `Rails.application.routes.routes`, parsing `path_params`, applying `route_filter`, flagging `external` routes in `lib/rails_openapi_generator/route_collector.rb`
- [X] T022 [P] [US1] Implement `Writer` serializing a document Hash to JSON or YAML with stable key ordering in `lib/rails_openapi_generator/writer.rb`
- [X] T023 [US1] Implement `OperationBuilder` producing a minimal `Endpoint` (method, path, deterministic operation_id, default response) in `lib/rails_openapi_generator/operation_builder.rb`
- [X] T024 [US1] Implement `DocumentBuilder` assembling `OpenApiDocument` (`openapi: "3.1.0"`, `info`, sorted `paths`) in `lib/rails_openapi_generator/document_builder.rb`
- [X] T025 [US1] Wire `Generator#generate` pipeline (RouteCollector → OperationBuilder → DocumentBuilder → Writer → Report), recording skipped routes with reasons in `lib/rails_openapi_generator/generator.rb`
- [X] T026 [US1] Implement the `openapi:generate` rake task wrapping `Generator#generate`, honoring `OUTPUT`/`FORMAT` env vars, printing the report in `lib/tasks/rails_openapi_generator.rake`
- [X] T027 [US1] Implement `CLI` (option parsing, boot Rails env from `--rails-root`, stdout report / stderr errors, exit codes) in `lib/rails_openapi_generator/cli.rb` and the `exe/rails-openapi-generator` shim
- [X] T028 [P] [US1] Contract spec verifying rake task, CLI, and library API produce an identical document for the same `Configuration` in `spec/integration/interface_parity_spec.rb`

**Checkpoint**: MVP — a valid OpenAPI document covering all endpoints is produced via rake task and CLI

---

## Phase 4: User Story 2 - Populate request parameters from existing validations (Priority: P2)

**Goal**: Each operation lists request parameters derived from the host app's `rails_param` `param!` declarations, with types, required flags, and constraints.

**Independent Test**: Run generation against dummy actions that declare `param!` calls and confirm parameters appear with matching name, type, required status, and constraints; actions with no `param!` still yield operations.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T029 [P] [US2] Unit spec for `SourceLocator` (maps a route to controller file + method) in `spec/unit/source_locator_spec.rb`
- [X] T030 [P] [US2] Unit spec for `YardParser` (parses a controller file once, exposes per-action AST) in `spec/unit/yard_parser_spec.rb`
- [X] T031 [P] [US2] Unit spec for `ParamExtractor` (literal `param!` calls → `ParamCall`; non-literal args flagged not `fully_resolved`) in `spec/unit/param_extractor_spec.rb`
- [X] T032 [P] [US2] Unit spec for `SchemaMapper` covering the R5 type/constraint mapping table in `spec/unit/schema_mapper_spec.rb`
- [X] T033 [P] [US2] Integration spec: parameters from `param!` appear in the generated document with correct location/type/required/constraints, including the no-params case, in `spec/integration/parameters_from_validations_spec.rb`

### Implementation for User Story 2

- [X] T034 [P] [US2] Implement `SourceLocator` resolving a `Route` to its controller file via `const_source_location` in `lib/rails_openapi_generator/source_locator.rb`
- [X] T035 [P] [US2] Implement `YardParser` parsing a controller file once into cached `ControllerSource`/`ActionSource` AST objects in `lib/rails_openapi_generator/yard_parser.rb`
- [X] T036 [US2] Implement `ParamExtractor` reading `param!` calls from an action AST into `ParamCall` records, setting `fully_resolved` for non-literal arguments in `lib/rails_openapi_generator/param_extractor.rb`
- [X] T037 [P] [US2] Implement `SchemaMapper` translating `ParamCall` type/constraints to OpenAPI 3.1 schema per the R5 table in `lib/rails_openapi_generator/schema_mapper.rb`
- [X] T038 [US2] Extend `OperationBuilder` to build `Parameter` records (path vs query vs body per R6, path-param precedence on name conflicts) and attach `parameters`/`request_body` in `lib/rails_openapi_generator/operation_builder.rb`
- [X] T039 [US2] Wire `SourceLocator`/`YardParser`/`ParamExtractor` into `Generator#generate`, adding warnings for non-literal `param!` and unparseable sources in `lib/rails_openapi_generator/generator.rb`

**Checkpoint**: Operations now carry typed, constrained request parameters; US1 still passes

---

## Phase 5: User Story 3 - Extract endpoint titles and descriptions from documentation comments (Priority: P3)

**Goal**: Each operation's summary and description come from the YARD comment above its controller action method.

**Independent Test**: Run generation against dummy actions with YARD comments and confirm summary/description match; actions without comments still yield operations.

### Tests for User Story 3 ⚠️ (write first, must fail)

- [X] T040 [P] [US3] Unit spec for `DocCommentExtractor` (first line → summary, rest → description; malformed/missing comment → nil + warning) in `spec/unit/doc_comment_extractor_spec.rb`
- [X] T041 [P] [US3] Integration spec: summary/description in the generated document match YARD comments, including the no-comment and orphan-comment cases, in `spec/integration/titles_from_comments_spec.rb`

### Implementation for User Story 3

- [X] T042 [US3] Implement `DocCommentExtractor` reading a YARD docstring from an `ActionSource` into a `DocComment` (summary/description), warning on malformed comments, in `lib/rails_openapi_generator/doc_comment_extractor.rb`
- [X] T043 [US3] Extend `OperationBuilder` to set `Endpoint` summary/description from `DocComment` in `lib/rails_openapi_generator/operation_builder.rb`
- [X] T044 [US3] Wire `DocCommentExtractor` into `Generator#generate`, recording warnings for malformed comments in `lib/rails_openapi_generator/generator.rb`

**Checkpoint**: All three user stories are independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Hardening and finalization across all stories

- [X] T045 [P] [Test] Determinism spec: generating twice against the dummy app yields byte-identical output (SC-008) in `spec/integration/determinism_spec.rb`
- [X] T046 [P] [Test] Resilience spec: a route that cannot be analyzed produces a warning and the run still includes every other endpoint (FR-016, SC-006) in `spec/integration/resilience_spec.rb`
- [X] T047 [P] Write `README.md` with installation, configuration, rake task, and CLI usage drawn from `quickstart.md`
- [X] T048 Run `quickstart.md` end-to-end against the dummy app and correct any discrepancies
- [X] T049 [P] Run RuboCop and resolve offenses across `lib/` and `exe/`
- [X] T050 Verify generation of a ~200-route fixture completes under 5 seconds (plan.md performance goal)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **User Stories (Phase 3–5)**: All depend on Foundational completion
- **Polish (Phase 6)**: Depends on all targeted user stories being complete

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational — the MVP
- **US2 (P2)**: Depends on Foundational; extends `OperationBuilder`/`Generator` from US1, so US1 should land first (independently testable on its own)
- **US3 (P3)**: Depends on Foundational; reuses `YardParser` introduced in US2, so US2 should land first

### Within Each User Story

- Tests written first and failing before implementation (Constitution III)
- Value objects/parsers before builders before `Generator` wiring
- `Generator` wiring task is the integration point — not parallel with builder tasks it depends on

### Parallel Opportunities

- Setup: T004, T005, T006, T008 in parallel
- Foundational: T009/T012 in parallel; test specs T010/T013 in parallel
- US1 tests T017–T020 in parallel; impl T021/T022 in parallel before T023→T024→T025
- US2 tests T029–T033 in parallel; impl T034/T035/T037 in parallel before T036→T038→T039
- US3 tests T040/T041 in parallel
- Polish: T045, T046, T047, T049 in parallel

---

## Parallel Example: User Story 1

```bash
# Tests first (all parallel):
Task: "Unit spec for RouteCollector in spec/unit/route_collector_spec.rb"
Task: "Unit spec for Writer in spec/unit/writer_spec.rb"
Task: "Unit spec for DocumentBuilder in spec/unit/document_builder_spec.rb"
Task: "Integration spec generate_all_endpoints in spec/integration/generate_all_endpoints_spec.rb"

# Then independent implementations (parallel):
Task: "Implement RouteCollector in lib/rails_openapi_generator/route_collector.rb"
Task: "Implement Writer in lib/rails_openapi_generator/writer.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: a valid OpenAPI document covering all endpoints is produced via rake task and CLI
5. Demo the MVP

### Incremental Delivery

1. Setup + Foundational → foundation ready
2. US1 → valid document for all endpoints (MVP)
3. US2 → operations gain typed request parameters
4. US3 → operations gain human-readable summaries/descriptions
5. Polish → determinism, resilience, docs, performance

---

## Notes

- [P] = different files, no dependency on an incomplete task
- [US#] maps a task to its user story; [Test] marks a non-story test task
- All test specs MUST fail before their implementation task is started
- Commit after each task or logical group
- Each user story checkpoint is independently testable against `spec/fixtures/dummy`
