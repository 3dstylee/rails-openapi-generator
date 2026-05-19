---
description: "Task list for Happy-Path Response Bodies implementation"
---

# Tasks: Happy-Path Response Bodies

**Input**: Design documents from `/specs/002-response-bodies/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Test tasks ARE included — Constitution Principle III (Test-First
Discipline) mandates every behavior change be covered by an automated test
written before/alongside implementation.

**Organization**: Tasks are grouped by user story (US1 P1, US2 P2, US3 P3).
This feature extends the existing gem from feature 001; it does not scaffold a
new project.

## Path Conventions

Existing Ruby gem: runtime code in `lib/rails_openapi_generator/`, tests in
`spec/` with the dummy Rails app under `spec/fixtures/dummy/`.

---

## Phase 1: Setup

**Purpose**: Version bump and test fixtures the feature needs

- [X] T001 Bump `VERSION` in `lib/rails_openapi_generator/version.rb` — adding response bodies changes generated output (Constitution V)
- [X] T002 [P] Add jbuilder view fixtures under `spec/fixtures/dummy/app/views/api/users/`: `index.json.jbuilder` (`json.array!` rendering the partial), `show.json.jbuilder` (renders the partial), and `_user.json.jbuilder` (a partial with `json.extract!`, a nested `json.* do … end` block, and a literal field)
- [X] T003 Update dummy controllers in `spec/fixtures/dummy/app/controllers/api/`: make `users#index` and `users#show` render implicitly (remove the literal `render json:`), keep a literal `render json: { … }` in `users#create`, and leave `posts#index` with no view and no literal render (the undeterminable case)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared literal evaluation and the value objects every story needs

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 [P] [Test] Unit spec for `LiteralEvaluator` (scalars, strings, symbols, arrays, hashes, ranges, regexps, `true`/`false`/`nil`, non-literal → unresolved) in `spec/unit/literal_evaluator_spec.rb`
- [X] T005 Implement the shared `LiteralEvaluator` module in `lib/rails_openapi_generator/literal_evaluator.rb`, extracting the Ripper-literal logic currently in `ParamExtractor` (research R7)
- [X] T006 Refactor `ParamExtractor` in `lib/rails_openapi_generator/param_extractor.rb` to delegate literal evaluation to `LiteralEvaluator`; confirm the existing `param_extractor_spec.rb` still passes
- [X] T007 [P] Implement the `Response` and `ResponseSchema` value objects in `lib/rails_openapi_generator/response.rb` per data-model.md
- [X] T008 Add a `response` field to the `Endpoint` struct in `lib/rails_openapi_generator/operation_builder.rb`

**Checkpoint**: Shared types compile; existing feature-001 specs still green

---

## Phase 3: User Story 1 - Document the success response body of each endpoint (Priority: P1) 🎯 MVP

**Goal**: Each operation's success response carries a body schema derived from the action's jbuilder view or a literal `render json:`.

**Independent Test**: Generate against the dummy app and confirm member endpoints get an object body schema, collection endpoints get an array body schema, and the document still passes OpenAPI 3.1 validation.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T009 [P] [US1] Unit spec for `ViewLocator` (resolves `<controller>/<action>.json.jbuilder`, honors literal `render` of another template, nil when absent) in `spec/unit/view_locator_spec.rb`
- [X] T010 [P] [US1] Unit spec for `JbuilderParser` (`json.x`, `json.* do … end`, `json.array!`, `json.extract!`, `json.partial!`, literal values) in `spec/unit/jbuilder_parser_spec.rb`
- [X] T011 [P] [US1] Unit spec for `RenderExtractor` (literal `render json:` → schema; non-literal flagged unresolved) in `spec/unit/render_extractor_spec.rb`
- [X] T012 [P] [US1] Unit spec for `ResponseBuilder` body assembly and literal-render-over-view precedence in `spec/unit/response_builder_spec.rb`
- [X] T013 [P] [US1] Integration spec: response bodies appear in the document, object vs array shape, nested schema, OpenAPI 3.1 validity, in `spec/integration/response_bodies_spec.rb`

### Implementation for User Story 1

- [X] T014 [P] [US1] Implement `ViewLocator` resolving an action to its `.json.jbuilder` template path in `lib/rails_openapi_generator/view_locator.rb`
- [X] T015 [P] [US1] Implement `RenderExtractor` reading literal `render json:` calls from an action AST via `LiteralEvaluator` in `lib/rails_openapi_generator/render_extractor.rb`
- [X] T016 [US1] Implement `JbuilderParser` parsing a `.json.jbuilder` file's Ripper AST into a `ResponseSchema` (handles `json.x`, do-blocks, `json.array!`, `json.extract!`, `json.partial!`, conditionals as a union; permissive leaf types per R3) in `lib/rails_openapi_generator/jbuilder_parser.rb`
- [X] T017 [US1] Implement `ResponseBuilder` selecting the body schema (literal `render json:` precedence over jbuilder view) in `lib/rails_openapi_generator/response_builder.rb`
- [X] T018 [US1] Extend `OperationBuilder` to accept a `response:` and attach it to the `Endpoint` in `lib/rails_openapi_generator/operation_builder.rb`
- [X] T019 [US1] Extend `DocumentBuilder` to emit each operation's `responses` with `content`/`application/json`/`schema` in `lib/rails_openapi_generator/document_builder.rb`
- [X] T020 [US1] Wire `ViewLocator`, `JbuilderParser`, `RenderExtractor`, and `ResponseBuilder` into `Generator#generate` in `lib/rails_openapi_generator/generator.rb`
- [X] T021 [US1] Extend the OpenAPI schema validator in `spec/support/openapi_schema.rb` to cover the response `content`/`schema` structure

**Checkpoint**: MVP — operations carry real success response body schemas

---

## Phase 4: User Story 2 - Stay valid when a response shape cannot be determined (Priority: P2)

**Goal**: Endpoints with no determinable response still produce a valid success response and are reported.

**Independent Test**: Generate against the dummy app (where `posts#index` has no view and no literal render) and confirm the endpoint still has a valid success response with no body schema and is named in the run report.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T022 [P] [US2] Integration spec: an undeterminable endpoint still has a valid success response, the document still validates, the endpoint is named in the report, and other endpoints are unaffected, in `spec/integration/response_resilience_spec.rb`

### Implementation for User Story 2

- [X] T023 [US2] `ResponseBuilder`: produce a `content`-less success `Response` when neither a jbuilder view nor a literal render resolves, in `lib/rails_openapi_generator/response_builder.rb`
- [X] T024 [US2] `Generator`: record a warning naming each operation whose response shape could not be determined, in `lib/rails_openapi_generator/generator.rb`

**Checkpoint**: Undeterminable responses degrade gracefully; US1 still passes

---

## Phase 5: User Story 3 - Use the conventional success status code (Priority: P3)

**Goal**: Each operation's success response is filed under 200 (read/update), 201 (create), or 204 (no content).

**Independent Test**: Generate against the dummy app and confirm GET responses use 200, the POST `create` response uses 201, and a no-content endpoint uses 204 with no body.

### Tests for User Story 3 ⚠️ (write first, must fail)

- [X] T025 [US3] Extend `spec/unit/response_builder_spec.rb` with status-code mapping cases (200/201/204) and `head :no_content` detection
- [X] T026 [US3] Extend `spec/integration/response_bodies_spec.rb` asserting GET→200, POST `create`→201, and a no-content endpoint→204 with no body

### Implementation for User Story 3

- [X] T027 [US3] `ResponseBuilder`: map the success status by HTTP method (GET/PUT/PATCH→200, POST→201, DELETE→204) in `lib/rails_openapi_generator/response_builder.rb`
- [X] T028 [US3] `RenderExtractor`/`ResponseBuilder`: detect an explicit `head :no_content`/`head 204` in the action and treat it as a 204 no-body response
- [X] T029 [US3] `DocumentBuilder`: file the response under its status code and omit `content` for 204 in `lib/rails_openapi_generator/document_builder.rb`

**Checkpoint**: All three user stories are independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Hardening and finalization

- [X] T030 [P] [Test] Extend `spec/integration/determinism_spec.rb` to assert response bodies are byte-identical across runs (FR-010)
- [X] T031 [P] [Test] Regression check: extend an integration spec to assert routes, parameters, summaries, descriptions, and tags are unchanged from feature 001 output (FR-012)
- [X] T032 [P] Update `README.md` with a "Response bodies" section (jbuilder + literal sources, status codes, permissive types, undeterminable behavior)
- [X] T033 Run `quickstart.md` end-to-end against the dummy app and correct any discrepancies
- [X] T034 [P] Run RuboCop across the new `lib/` files and resolve offenses

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **User Stories (Phase 3–5)**: All depend on Foundational completion
- **Polish (Phase 6)**: Depends on all targeted user stories

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational — the MVP
- **US2 (P2)**: Depends on Foundational; extends `ResponseBuilder`/`Generator` from US1, so US1 should land first
- **US3 (P3)**: Depends on Foundational; extends `ResponseBuilder`/`DocumentBuilder` from US1, so US1 should land first

### Within Each User Story

- Tests written first and failing before implementation (Constitution III)
- `LiteralEvaluator` (T005) before `RenderExtractor` (T015)
- `ViewLocator`/`JbuilderParser`/`RenderExtractor` before `ResponseBuilder` (T017)
- `ResponseBuilder` before `OperationBuilder`/`Generator` wiring
- The `Generator` wiring task is the integration point — not parallel with the builders it consumes

### Parallel Opportunities

- Setup: T002 in parallel with T001
- Foundational: T004 and T007 in parallel
- US1 tests T009–T013 in parallel; impl T014/T015 in parallel before T016→T017→T018→T019→T020
- Polish: T030, T031, T032, T034 in parallel

---

## Parallel Example: User Story 1

```bash
# Tests first (all parallel):
Task: "Unit spec for ViewLocator in spec/unit/view_locator_spec.rb"
Task: "Unit spec for JbuilderParser in spec/unit/jbuilder_parser_spec.rb"
Task: "Unit spec for RenderExtractor in spec/unit/render_extractor_spec.rb"
Task: "Unit spec for ResponseBuilder in spec/unit/response_builder_spec.rb"
Task: "Integration spec response_bodies in spec/integration/response_bodies_spec.rb"

# Then independent implementations (parallel):
Task: "Implement ViewLocator in lib/rails_openapi_generator/view_locator.rb"
Task: "Implement RenderExtractor in lib/rails_openapi_generator/render_extractor.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: operations carry real response body schemas; document still validates
5. Demo the MVP

### Incremental Delivery

1. Setup + Foundational → shared types ready
2. US1 → response bodies from jbuilder + literal renders (MVP)
3. US2 → graceful handling of undeterminable responses
4. US3 → conventional 200/201/204 status codes
5. Polish → determinism, regression check, docs

---

## Notes

- [P] = different files, no dependency on an incomplete task
- [US#] maps a task to its user story; [Test] marks a non-story test task
- All test specs MUST fail before their implementation task is started
- This feature is additive — feature 001 output (routes, parameters, tags,
  source references) must remain unchanged (FR-012, verified by T031)
- Commit after each task or logical group
