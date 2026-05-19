---
description: "Task list for Implicit Params Detection"
---

# Tasks: Implicit Params Detection

**Input**: Design documents from `/specs/006-implicit-params/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Test tasks ARE included — Constitution Principle III (Test-First
Discipline) mandates every behavior change be covered by an automated test
written before/alongside implementation.

**Organization**: Tasks are grouped by user story (US1 P1, US2 P2, US3 P3).
This feature extends the existing gem (features 001–005).

## Path Conventions

Existing Ruby gem: runtime code in `lib/rails_openapi_generator/`, tests in
`spec/` with the dummy Rails app under `spec/fixtures/dummy/`.

---

## Phase 1: Setup

**Purpose**: Version bump and test fixtures the feature needs

- [X] T001 Bump `VERSION` to `0.6.0` in `lib/rails_openapi_generator/version.rb` — implicit-params detection changes generated output (Constitution V)
- [X] T002 [P] Add `spec/fixtures/dummy/app/controllers/api/inputs_controller.rb` with a GET action reading `params[:id]` (a path key), `params[:query]`, and `params[:format]` (a Rails-internal key); a POST action using `params.require`/`permit`/`fetch`; and a POST action that reads `params` through a private helper method
- [X] T003 Add routes for the inputs actions in `spec/fixtures/dummy/config/routes.rb`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared recursive method traversal and the renamed depth setting

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 [P] [Test] Unit spec for `ControllerMethodWalker` (returns the action body plus its resolved receiverless helper bodies; depth-bounded; cycle-guarded) in `spec/unit/controller_method_walker_spec.rb`
- [X] T005 Implement `ControllerMethodWalker` in `lib/rails_openapi_generator/controller_method_walker.rb` — extract the recursive action-and-helper traversal (`MethodResolver` use, depth cap, cycle guard) currently inside `WrapperDownloadResolver`
- [X] T006 Refactor `WrapperDownloadResolver` in `lib/rails_openapi_generator/wrapper_download_resolver.rb` to use `ControllerMethodWalker`; confirm the feature-004 specs still pass
- [X] T007 [P] [Test] Update `spec/unit/configuration_spec.rb` for the renamed `method_resolution_depth` setting
- [X] T008 Rename `download_resolution_depth` to `method_resolution_depth` in `lib/rails_openapi_generator/configuration.rb` and update every reference (`Generator`, `WrapperDownloadResolver` wiring)

**Checkpoint**: The shared walker works; existing feature-001–005 specs still green

---

## Phase 3: User Story 1 - Document parameters read directly from `params` (Priority: P1) 🎯 MVP

**Goal**: Parameters read via `params[:key]` / `params["key"]` are documented.

**Independent Test**: Generate against the dummy app and confirm `params[:query]` appears as a parameter, `params[:id]` is not duplicated (it is a path param), and `params[:format]` is not documented.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T009 [P] [US1] Unit spec for `ImplicitParamScanner` index-access detection (`params[:key]`, `params["key"]`; dynamic `params[var]` skipped) in `spec/unit/implicit_param_scanner_spec.rb`
- [X] T010 [P] [US1] Integration spec: `params[:query]` is documented, `params[:id]` is not duplicated, `params[:format]`/`controller`/`action` are excluded, in `spec/integration/implicit_params_spec.rb`

### Implementation for User Story 1

- [X] T011 [US1] Implement `ImplicitParamScanner#scan(controller_class, action_node)` detecting `params[:key]` index access in the action body (`:aref` on the `params` receiver, literal keys only) in `lib/rails_openapi_generator/implicit_param_scanner.rb`
- [X] T012 [US1] Extend `OperationBuilder#build` to accept `implicit_params:` and merge them as parameters — placed like `param!` params (query vs body by HTTP method), permissive "any" schema — deduplicated against path and `param!` names and minus `controller`/`action`/`format`, in `lib/rails_openapi_generator/operation_builder.rb`
- [X] T013 [US1] Wire `ImplicitParamScanner` into `Generator` (build it, pass discovered keys to `OperationBuilder#build`) in `lib/rails_openapi_generator/generator.rb`

**Checkpoint**: MVP — `params[:key]` parameters are documented

---

## Phase 4: User Story 2 - Document parameters from strong-params calls (Priority: P2)

**Goal**: Keys named in `require`/`permit`/`fetch`/`dig` calls are documented.

**Independent Test**: Generate against the dummy app and confirm the keys from `params.require(:project)`, `params.permit(:name, :archived)`, and `params.fetch(:token)` all appear as parameters.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T014 [P] [US2] Extend `spec/unit/implicit_param_scanner_spec.rb` with `require`/`permit`/`fetch`/`dig` cases, including a `require(:x).permit(:a, :b)` chain
- [X] T015 [P] [US2] Extend `spec/integration/implicit_params_spec.rb` asserting the strong-params keys appear on the POST operation

### Implementation for User Story 2

- [X] T016 [US2] Extend `ImplicitParamScanner` to detect `require`/`permit`/`fetch`/`dig` calls on the `params` receiver (and on a `params` strong-params chain), collecting literal symbol/string arguments, in `lib/rails_openapi_generator/implicit_param_scanner.rb`

**Checkpoint**: Strong-params keys are documented; US1 still passes

---

## Phase 5: User Story 3 - Follow `params` use into helper methods (Priority: P3)

**Goal**: Parameters used inside receiverless helper methods the action calls are discovered.

**Independent Test**: Generate against the dummy app and confirm the key read by a helper method (`params[:file]` in `store_upload`) appears on the action that calls it.

### Tests for User Story 3 ⚠️ (write first, must fail)

- [X] T017 [P] [US3] Extend `spec/unit/implicit_param_scanner_spec.rb` with recursive cases (a helper that reads `params`; a chain of helpers; cyclic helpers complete without looping)

### Implementation for User Story 3

- [X] T018 [US3] Make `ImplicitParamScanner` scan every body returned by `ControllerMethodWalker.reachable_bodies` (the action plus its resolved receiverless helpers) rather than the action body alone, in `lib/rails_openapi_generator/implicit_param_scanner.rb`

**Checkpoint**: All three user stories are independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Hardening and finalization

- [X] T019 [P] [Test] Extend `spec/integration/determinism_spec.rb` to assert implicit parameters are emitted in a stable order across runs (FR-011)
- [X] T020 [P] [Test] Regression: extend `spec/integration/feature_001_regression_spec.rb` to assert path parameters and `param!`-derived parameters are unchanged — only new implicit parameters are added (FR-010)
- [X] T021 [P] Update `README.md` with a note on implicit-params detection and the `method_resolution_depth` rename
- [X] T022 [P] Add a `0.6.0` entry to `CHANGELOG.md` describing implicit-params detection and the `download_resolution_depth` → `method_resolution_depth` rename
- [X] T023 Run `quickstart.md` end-to-end against the dummy app and correct any discrepancies
- [X] T024 [P] Run RuboCop across the new/changed `lib/` files and resolve offenses

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **User Stories (Phase 3–5)**: All depend on Foundational completion
- **Polish (Phase 6)**: Depends on all targeted user stories

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational — the MVP
- **US2 (P2)**: Depends on US1 — extends `ImplicitParamScanner`'s detection
- **US3 (P3)**: Depends on US1 — switches `ImplicitParamScanner` to the walker

### Within Each User Story

- Tests written first and failing before implementation (Constitution III)
- `ControllerMethodWalker` (T005) before `WrapperDownloadResolver` refactor (T006)
- `ImplicitParamScanner` (T011) before the `OperationBuilder`/`Generator` wiring
- T011 → T016 → T018 all modify `implicit_param_scanner.rb` — sequential

### Parallel Opportunities

- Setup: T002 in parallel with T001
- Foundational: T004 and T007 (tests) in parallel
- US1: tests T009/T010 in parallel before the implementation tasks
- Polish: T019, T020, T021, T022, T024 in parallel

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (shared walker + renamed setting)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: `params[:key]` parameters are documented
5. Demo the MVP

### Incremental Delivery

1. Setup + Foundational → shared walker ready
2. US1 → `params[:key]` detection (MVP — fixes the reported gap)
3. US2 → strong-params keys
4. US3 → `params` use inside helper methods
5. Polish → determinism, regression, docs

---

## Notes

- [P] = different files, no dependency on an incomplete task
- [US#] maps a task to its user story; [Test] marks a non-story test task
- All test specs MUST fail before their implementation task is started
- This feature is additive — path parameters, `param!` parameters, and all
  other operation content (features 001–005) must stay unchanged (FR-010, T020)
- Commit after each task or logical group
