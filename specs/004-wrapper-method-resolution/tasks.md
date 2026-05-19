---
description: "Task list for Wrapper Method Resolution for File Downloads"
---

# Tasks: Wrapper Method Resolution for File Downloads

**Input**: Design documents from `/specs/004-wrapper-method-resolution/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Test tasks ARE included — Constitution Principle III (Test-First
Discipline) mandates every behavior change be covered by an automated test
written before/alongside implementation.

**Organization**: Tasks are grouped by user story (US1 P1, US2 P2, US3 P3).
This feature extends the existing gem (features 001–003).

## Path Conventions

Existing Ruby gem: runtime code in `lib/rails_openapi_generator/`, tests in
`spec/` with the dummy Rails app under `spec/fixtures/dummy/`.

---

## Phase 1: Setup

**Purpose**: Version bump and test fixtures the feature needs

- [X] T001 Bump `VERSION` to `0.4.0` in `lib/rails_openapi_generator/version.rb` — wrapper-resolved downloads change generated output (Constitution V)
- [X] T002 [P] Add a download-wrapper concern `spec/fixtures/dummy/app/controllers/concerns/file_streaming.rb` with a private method that calls `send_file`
- [X] T003 [P] Add `spec/fixtures/dummy/app/controllers/api/reports_controller.rb` with actions that download via a single same-controller wrapper, via a chain of wrappers, via the concern method, and via a cyclic pair of wrappers (never reaching `send_file`)
- [X] T004 Add routes for the reports actions in `spec/fixtures/dummy/config/routes.rb`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Configuration, controller-class access, and method resolution

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 [P] [Test] Extend `spec/unit/configuration_spec.rb` for `download_resolution_depth` default (5) and validation (integer >= 1)
- [X] T006 Add `download_resolution_depth` (default 5, validated as integer >= 1) to `Configuration` in `lib/rails_openapi_generator/configuration.rb`
- [X] T007 [P] [Test] Unit spec for `MethodResolver` (resolves a controller's own method, an included-module method, and a parent-controller method; returns nil for an unknown name or a gem/framework method) in `spec/unit/method_resolver_spec.rb`
- [X] T008 Implement `MethodResolver` and the `ResolvedMethod` value object — locate a `(controller class, method name)` via `instance_method().source_location`, restricted to app files, and parse the def node via `YardParser` — in `lib/rails_openapi_generator/method_resolver.rb`
- [X] T009 Extend `SourceLocator` to also expose the resolved controller `Class` (not only its file path) in `lib/rails_openapi_generator/source_locator.rb`

**Checkpoint**: Method resolution works in isolation; existing feature-001/002/003 specs still green

---

## Phase 3: User Story 1 - Detect a download made through a wrapper method (Priority: P1) 🎯 MVP

**Goal**: An action that calls a helper which itself calls `send_file`/`send_data` is classified as a file-download endpoint.

**Independent Test**: Generate against the dummy app and confirm the action that downloads through a single same-controller / concern / parent wrapper is marked as a file-download endpoint.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T010 [P] [US1] Unit spec for `WrapperDownloadResolver` single-level resolution (action → one wrapper → `send_file` → true; wrapper that never calls `send_file` → false) in `spec/unit/wrapper_download_resolver_spec.rb`
- [X] T011 [P] [US1] Integration spec: the single-wrapper download action is classified as a file-download endpoint (content type, tag, flag) in `spec/integration/wrapper_download_spec.rb`

### Implementation for User Story 1

- [X] T012 [US1] Implement `WrapperDownloadResolver` — scan a method body for receiverless call names, detect a `send_file`/`send_data` leaf, and resolve one level of wrapper via `MethodResolver` — in `lib/rails_openapi_generator/wrapper_download_resolver.rb`
- [X] T013 [US1] Wire `WrapperDownloadResolver` into `RenderClassifier`'s `:undeterminable` branch so a resolved download yields `kind: :file_download`, in `lib/rails_openapi_generator/render_classifier.rb`
- [X] T014 [US1] Wire the resolver and the controller class into `Generator` (build the resolver from `Configuration`, pass the controller class + action node to classification) in `lib/rails_openapi_generator/generator.rb`

**Checkpoint**: MVP — a download through a single wrapper is detected

---

## Phase 4: User Story 2 - Follow chains of wrapper methods (Priority: P2)

**Goal**: A download reached through a chain of wrapper methods (A → B → `send_file`) is detected.

**Independent Test**: Generate against the dummy app and confirm the chained-wrapper action and the concern-wrapper action are classified as file-download endpoints.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T015 [P] [US2] Extend `spec/unit/wrapper_download_resolver_spec.rb` with chained-wrapper cases (A → B → `send_file` → true; a chain that never reaches a download → false)
- [X] T016 [P] [US2] Extend `spec/integration/wrapper_download_spec.rb` asserting the chained-wrapper and concern-wrapper actions are classified as file downloads

### Implementation for User Story 2

- [X] T017 [US2] Make `WrapperDownloadResolver` recursive — for each resolved wrapper, follow its own receiverless calls in turn — in `lib/rails_openapi_generator/wrapper_download_resolver.rb`

**Checkpoint**: Downloads through multi-level wrapper chains are detected; US1 still passes

---

## Phase 5: User Story 3 - Keep resolution bounded and safe (Priority: P3)

**Goal**: Recursive resolution stops at the configured depth, never loops on cycles, and ends quietly on unresolvable calls.

**Independent Test**: Generate against the dummy app (which has a cyclic wrapper pair) and confirm the run completes without hanging and the cyclic action stays undeterminable; a chain deeper than the configured depth is abandoned.

### Tests for User Story 3 ⚠️ (write first, must fail)

- [X] T018 [P] [US3] Extend `spec/unit/wrapper_download_resolver_spec.rb` with bound/safety cases: a chain deeper than the configured depth → false; a cycle does not loop; an unresolvable call ends the branch
- [X] T019 [P] [US3] Extend `spec/integration/wrapper_download_spec.rb` asserting the cyclic-wrapper action completes the run and stays undeterminable

### Implementation for User Story 3

- [X] T020 [US3] Add the configurable depth cap (`Configuration#download_resolution_depth`) to `WrapperDownloadResolver` in `lib/rails_openapi_generator/wrapper_download_resolver.rb`
- [X] T021 [US3] Add the cycle guard — a visited-set keyed by resolved `"file:line"` — to `WrapperDownloadResolver` in `lib/rails_openapi_generator/wrapper_download_resolver.rb`
- [X] T022 [US3] Ensure unresolvable calls (unknown names, gem/framework methods, app-external files) end their branch quietly without error in `lib/rails_openapi_generator/wrapper_download_resolver.rb`

**Checkpoint**: All three user stories are independently functional and the recursion is safe

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Hardening and finalization

- [X] T023 [P] [Test] Extend `spec/integration/determinism_spec.rb` to assert wrapper-resolved downloads are byte-identical across runs (FR-011)
- [X] T024 [P] [Test] Regression: extend `spec/integration/feature_001_regression_spec.rb` to assert JSON, HTML-page, direct-download, and genuinely-undeterminable classifications are unchanged (FR-010)
- [X] T025 [P] Update `README.md` with a note on wrapper-resolved downloads and the `download_resolution_depth` setting
- [X] T026 [P] Add a `0.4.0` entry to `CHANGELOG.md` describing wrapper-method resolution
- [X] T027 Run `quickstart.md` end-to-end against the dummy app and correct any discrepancies
- [X] T028 [P] Run RuboCop across the new/changed `lib/` files and resolve offenses

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **User Stories (Phase 3–5)**: All depend on Foundational completion
- **Polish (Phase 6)**: Depends on all targeted user stories

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational — the MVP
- **US2 (P2)**: Depends on US1 — extends `WrapperDownloadResolver` with recursion
- **US3 (P3)**: Depends on US2 — bounds the recursion. In practice US3 should
  land **together with US2**: recursion without a depth cap and cycle guard is
  unsafe, so do not ship US2 alone.

### Within Each User Story

- Tests written first and failing before implementation (Constitution III)
- `MethodResolver` (T008) before `WrapperDownloadResolver` (T012)
- `WrapperDownloadResolver` before the `RenderClassifier`/`Generator` wiring
- T012 → T017 → T020 → T021 → T022 all modify `wrapper_download_resolver.rb` —
  strictly sequential, not parallel

### Parallel Opportunities

- Setup: T002 and T003 in parallel
- Foundational: test tasks T005/T007 in parallel; T006/T009 in parallel
- US1: tests T010/T011 in parallel before the implementation tasks
- Polish: T023, T024, T025, T026, T028 in parallel

---

## Parallel Example: Foundational

```bash
# Tests first (parallel):
Task: "Extend configuration_spec for download_resolution_depth in spec/unit/configuration_spec.rb"
Task: "Unit spec for MethodResolver in spec/unit/method_resolver_spec.rb"

# Then (parallel):
Task: "Add download_resolution_depth to Configuration in lib/rails_openapi_generator/configuration.rb"
Task: "Expose the controller class from SourceLocator in lib/rails_openapi_generator/source_locator.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (method resolution works)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: a download through a single wrapper is detected
5. Demo the MVP

### Incremental Delivery

1. Setup + Foundational → method resolution ready
2. US1 → single-wrapper downloads detected (MVP)
3. US2 + US3 together → recursive resolution, bounded and cycle-safe
4. Polish → determinism, regression, docs

---

## Notes

- [P] = different files, no dependency on an incomplete task
- [US#] maps a task to its user story; [Test] marks a non-story test task
- All test specs MUST fail before their implementation task is started
- This feature is additive — only previously-undeterminable actions may change;
  JSON / HTML / direct-download output (features 001–003) must stay unchanged
  (FR-010, verified by T024)
- Commit after each task or logical group
