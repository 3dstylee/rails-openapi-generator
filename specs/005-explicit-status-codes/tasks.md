---
description: "Task list for Explicit Success Status Codes"
---

# Tasks: Explicit Success Status Codes

**Input**: Design documents from `/specs/005-explicit-status-codes/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Test tasks ARE included — Constitution Principle III (Test-First
Discipline) mandates every behavior change be covered by an automated test
written before/alongside implementation.

**Organization**: Tasks are grouped by user story (US1 P1, US2 P2, US3 P3).
This feature extends the existing gem (features 001–004).

## Path Conventions

Existing Ruby gem: runtime code in `lib/rails_openapi_generator/`, tests in
`spec/` with the dummy Rails app under `spec/fixtures/dummy/`.

---

## Phase 1: Setup

**Purpose**: Version bump and test fixtures the feature needs

- [X] T001 Bump `VERSION` to `0.5.0` in `lib/rails_openapi_generator/version.rb` — explicit-status detection changes generated output (Constitution V)
- [X] T002 [P] Add `spec/fixtures/dummy/app/controllers/api/statuses_controller.rb` with a POST and a PUT action that both do `head :ok`, a POST action that does `render json: …, status: :created`, and a POST action with an error-status guard followed by `head :ok`
- [X] T003 Add routes for the statuses actions in `spec/fixtures/dummy/config/routes.rb`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Extract the explicit status from the action AST

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 [P] [Test] Extend `spec/unit/render_extractor_spec.rb` for `explicit_status` (from `head :symbol`, `head <int>`, and `render status:`; last happy-path wins; error statuses ignored; unmappable symbol → nil) and `head`
- [X] T005 Replace `RenderResult#no_content` with `explicit_status` (Integer/nil) and `head` (Boolean) in `lib/rails_openapi_generator/render_extractor.rb`; read `head` call statuses and `render status:` options, resolve via `STATUS_CODES`, and keep the last happy-path (2xx/3xx) code

**Checkpoint**: `RenderExtractor` reports an explicit status; existing feature-001–004 specs still load

---

## Phase 3: User Story 1 - Document the status code the action actually sets (Priority: P1) 🎯 MVP

**Goal**: Each operation's success response is filed under the status the action explicitly sets, not the HTTP-method guess.

**Independent Test**: Generate against the dummy app and confirm the `head :ok` POST and the `head :ok` PUT are both documented under `200`, and the `render … status: :created` action under `201`.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T006 [P] [US1] Extend `spec/unit/response_builder_spec.rb` asserting the status comes from `explicit_status` when present (200/201/etc.), across HTTP methods
- [X] T007 [P] [US1] Integration spec: the `head :ok` POST and PUT are documented under `200`, and the `render status: :created` action under `201`, in `spec/integration/explicit_status_spec.rb`

### Implementation for User Story 1

- [X] T008 [US1] Update `ResponseBuilder` to use `render_result.explicit_status` as the status when present (falling back to the HTTP-method convention), and document a `204` response with no body, in `lib/rails_openapi_generator/response_builder.rb`

**Checkpoint**: MVP — explicit status codes are documented accurately

---

## Phase 4: User Story 2 - A head response has no body (Priority: P2)

**Goal**: A success response produced by a `head` call is documented with no response body schema.

**Independent Test**: Generate against the dummy app and confirm the `head :ok` actions have a success response with no `content`.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T009 [P] [US2] Extend `spec/unit/response_builder_spec.rb` and `spec/integration/explicit_status_spec.rb` asserting a `head` action's response has no body; `head :no_content` → `204` no body

### Implementation for User Story 2

- [X] T010 [US2] Update `ResponseBuilder` to omit the response body when `render_result.head` is true in `lib/rails_openapi_generator/response_builder.rb`

**Checkpoint**: `head` responses are body-less; US1 still passes

---

## Phase 5: User Story 3 - Fall back to the HTTP-method convention (Priority: P3)

**Goal**: An action with no explicit (mappable, happy-path) status keeps the HTTP-method convention status.

**Independent Test**: Generate against the dummy app and confirm an action with no explicit status, and an action whose only status is an error status, both use the HTTP-method convention.

### Tests for User Story 3 ⚠️ (write first, must fail)

- [X] T011 [P] [US3] Extend `spec/integration/explicit_status_spec.rb` asserting an action with no explicit status uses the HTTP-method convention, the error-guard action uses its happy `head :ok` status (200), and an unmappable status symbol falls back to the convention

**Checkpoint**: All three user stories are independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Hardening and finalization

- [X] T012 [P] [Test] Regression: extend `spec/integration/feature_001_regression_spec.rb` to assert response kinds, bodies, tags, and `x-` marks are unchanged — only status codes may change (FR-010)
- [X] T013 [P] [Test] Extend `spec/integration/determinism_spec.rb` to assert explicit-status operations are byte-identical across runs (FR-011)
- [X] T014 [P] Update `README.md` with a note on explicit status-code detection
- [X] T015 [P] Add a `0.5.0` entry to `CHANGELOG.md` describing explicit success status codes
- [X] T016 Run `quickstart.md` end-to-end against the dummy app and correct any discrepancies
- [X] T017 [P] Run RuboCop across the changed `lib/` files and resolve offenses

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **User Stories (Phase 3–5)**: All depend on Foundational completion
- **Polish (Phase 6)**: Depends on all targeted user stories

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational — the MVP
- **US2 (P2)**: Depends on US1 — extends `ResponseBuilder`'s body logic
- **US3 (P3)**: Depends on US1 — the fallback is the `explicit_status || convention`
  rule implemented in T008; US3 is its verification

### Within Each User Story

- Tests written first and failing before implementation (Constitution III)
- `RenderExtractor` (T005) before `ResponseBuilder` (T008)
- T008 → T010 both modify `response_builder.rb` — sequential, not parallel

### Parallel Opportunities

- Setup: T002 in parallel with T001
- US1: tests T006/T007 in parallel before T008
- Polish: T012, T013, T014, T015, T017 in parallel

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (`RenderExtractor` reports `explicit_status`)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: `head :ok` actions are documented under `200`
5. Demo the MVP

### Incremental Delivery

1. Setup + Foundational → explicit status available
2. US1 → accurate status codes (MVP)
3. US2 → `head` responses are body-less
4. US3 → method-convention fallback verified
5. Polish → regression, determinism, docs

---

## Notes

- [P] = different files, no dependency on an incomplete task
- [US#] maps a task to its user story; [Test] marks a non-story test task
- All test specs MUST fail before their implementation task is started
- This feature changes only status codes (and `head` body absence); response
  kind, body schema, tags, and `x-` marks must stay unchanged (FR-010, T012)
- Commit after each task or logical group
