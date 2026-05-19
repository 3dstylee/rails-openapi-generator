---
description: "Task list for HTML Page & File Download Endpoints implementation"
---

# Tasks: HTML Page & File Download Endpoints

**Input**: Design documents from `/specs/003-html-page-endpoints/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Test tasks ARE included — Constitution Principle III (Test-First
Discipline) mandates every behavior change be covered by an automated test
written before/alongside implementation.

**Organization**: Tasks are grouped by user story (US1 P1, US2 P2, US3 P3).
This feature extends the existing gem (features 001 & 002).

## Path Conventions

Existing Ruby gem: runtime code in `lib/rails_openapi_generator/`, tests in
`spec/` with the dummy Rails app under `spec/fixtures/dummy/`.

---

## Phase 1: Setup

**Purpose**: Version bump and test fixtures the feature needs

- [X] T001 Bump `VERSION` to `0.3.0` in `lib/rails_openapi_generator/version.rb` — non-JSON endpoint marks change generated output (Constitution V)
- [X] T002 [P] Add a dummy controller `spec/fixtures/dummy/app/controllers/api/pages_controller.rb` with a `show` action that renders an HTML view implicitly (no `render` line) and a `download` action that calls `send_file`
- [X] T003 [P] Add the HTML view fixture `spec/fixtures/dummy/app/views/api/pages/show.html.erb`
- [X] T004 Add routes for `api/pages#show` and `api/pages#download` in `spec/fixtures/dummy/config/routes.rb`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Detection signals, view resolution, and the classifier every story builds on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 [P] [Test] Extend `spec/unit/render_extractor_spec.rb` with cases for `send_file`/`send_data`, `render html:`, and explicit `render template:`/`render :action`
- [X] T006 Extend `RenderExtractor` and `RenderResult` in `lib/rails_openapi_generator/render_extractor.rb` with `file_download`, `html_inline`, and `template` signals
- [X] T007 [P] [Test] Extend `spec/unit/view_locator_spec.rb` to cover resolving `.html.*` views and reporting view kind
- [X] T008 Extend `ViewLocator` in `lib/rails_openapi_generator/view_locator.rb` to resolve `.html.*` views and return a `ViewMatch` (kind `:json`/`:html`, path, name)
- [X] T009 [P] [Test] Unit spec for `RenderClassifier` (precedence: JSON → send_file → render html: → explicit template → implicit view → undeterminable) in `spec/unit/render_classifier_spec.rb`
- [X] T010 Implement `RenderClassifier` and the `Classification` value object in `lib/rails_openapi_generator/render_classifier.rb` per research R3
- [X] T011 Add `kind` and `page_reference` fields to `Response` in `lib/rails_openapi_generator/response.rb`

**Checkpoint**: Classification works in isolation; existing feature-001/002 specs still green

---

## Phase 3: User Story 1 - Tell non-JSON endpoints apart from JSON APIs (Priority: P1) 🎯 MVP

**Goal**: HTML-page and file-download endpoints are marked with a non-JSON response content type, a description note, and a dedicated tag.

**Independent Test**: Generate against the dummy app and confirm the HTML-page action shows a `text/html` response, the `send_file` action shows an `application/octet-stream` response, both carry a description note and their kind tag, and JSON endpoints are unchanged.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T012 [P] [US1] Integration spec: HTML-page and file-download endpoints get the right content type, description note, and tag; JSON endpoints unchanged; document still validates — in `spec/integration/html_page_endpoints_spec.rb`

### Implementation for User Story 1

- [X] T013 [US1] Extend `ResponseBuilder` to consume a `Classification` and produce a kind-aware `Response` (`text/html` for HTML pages, `application/octet-stream` for downloads) in `lib/rails_openapi_generator/response_builder.rb`
- [X] T014 [US1] Extend `OperationBuilder` to append the page/download note to the description (`_Renders an HTML page (…)._` / `_Sends a file download._`) in `lib/rails_openapi_generator/operation_builder.rb`
- [X] T015 [US1] Extend `DocumentBuilder` to emit the non-JSON response content type per `response.kind` in `lib/rails_openapi_generator/document_builder.rb`
- [X] T016 [US1] Extend `DocumentBuilder` to add the `"HTML Pages"` / `"File Downloads"` tag to the operation and the top-level `tags` list, alongside the controller tag, in `lib/rails_openapi_generator/document_builder.rb`
- [X] T017 [US1] Wire `RenderClassifier` into `Generator#generate` so each endpoint's `Response` carries its classification, in `lib/rails_openapi_generator/generator.rb`
- [X] T018 [US1] Update the OpenAPI schema validator in `spec/support/openapi_schema.rb` to accept `text/html`/`application/octet-stream` response content and `x-` extension keys

**Checkpoint**: MVP — non-JSON endpoints are visibly distinguished from JSON APIs

---

## Phase 4: User Story 2 - Programmatically identify non-JSON endpoints (Priority: P2)

**Goal**: Each HTML-page and file-download operation carries a machine-readable vendor extension.

**Independent Test**: Generate against the dummy app and confirm the HTML-page operation has `x-renders-html: true` (and `x-html-template` when known) and the download operation has `x-sends-file: true`, while JSON operations have neither.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T019 [P] [US2] Extend `spec/integration/html_page_endpoints_spec.rb` asserting `x-renders-html`/`x-html-template` on HTML pages, `x-sends-file` on downloads, and neither on JSON operations

### Implementation for User Story 2

- [X] T020 [US2] Extend `DocumentBuilder` to add the `x-renders-html`/`x-html-template`/`x-sends-file` vendor extensions per `response.kind` in `lib/rails_openapi_generator/document_builder.rb`

**Checkpoint**: Non-JSON endpoints are machine-identifiable; US1 still passes

---

## Phase 5: User Story 3 - See how many endpoints are pages/downloads (Priority: P3)

**Goal**: The run report states the count of HTML-page and file-download endpoints.

**Independent Test**: Generate against the dummy app and confirm the report names a non-zero HTML-page count and file-download count.

### Tests for User Story 3 ⚠️ (write first, must fail)

- [X] T021 [P] [US3] Extend `spec/unit/report_spec.rb` for `html_page_count`/`file_download_count` accessors and their summary lines

### Implementation for User Story 3

- [X] T022 [US3] Add `html_page_count` and `file_download_count` to `GenerationReport` (accessors + `#summary` lines) in `lib/rails_openapi_generator/report.rb`
- [X] T023 [US3] Increment the report's HTML-page / file-download counters by classification in `lib/rails_openapi_generator/generator.rb`

**Checkpoint**: All three user stories are independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Hardening and finalization

- [X] T024 [P] [Test] Extend `spec/integration/determinism_spec.rb` to assert non-JSON marks (content type, tags, extensions) are byte-identical across runs (FR-012)
- [X] T025 [P] [Test] Regression: extend `spec/integration/feature_001_regression_spec.rb` to assert JSON endpoints' responses, tags, and descriptions are unchanged (FR-013)
- [X] T026 [P] Update `README.md` with an "HTML pages & file downloads" section
- [X] T027 [P] Add a `0.3.0` entry to `CHANGELOG.md` describing the additive non-JSON marks
- [X] T028 Run `quickstart.md` end-to-end against the dummy app and correct any discrepancies
- [X] T029 [P] Run RuboCop across the new/changed `lib/` files and resolve offenses

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **User Stories (Phase 3–5)**: All depend on Foundational completion
- **Polish (Phase 6)**: Depends on all targeted user stories

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational — the MVP
- **US2 (P2)**: Depends on Foundational; extends `DocumentBuilder` from US1, so US1 should land first
- **US3 (P3)**: Depends on Foundational; independent of US1/US2 (touches `report.rb`/`generator.rb`)

### Within Each User Story

- Tests written first and failing before implementation (Constitution III)
- `RenderExtractor`/`ViewLocator` extensions before `RenderClassifier` (T010)
- `RenderClassifier` + `Response` before `ResponseBuilder` (T013)
- `ResponseBuilder` before `DocumentBuilder`/`OperationBuilder` consume `kind`
- The `Generator` wiring task is the integration point — last in its story

### Parallel Opportunities

- Setup: T002 and T003 in parallel
- Foundational: test tasks T005/T007/T009 in parallel; T006 and T008 in parallel before T010
- US1: T013/T014 in parallel before the sequential `DocumentBuilder` tasks T015→T016→T017
- Polish: T024, T025, T026, T027, T029 in parallel

---

## Parallel Example: Foundational

```bash
# Tests first (all parallel):
Task: "Extend render_extractor_spec for send_file/html/template in spec/unit/render_extractor_spec.rb"
Task: "Extend view_locator_spec for html resolution in spec/unit/view_locator_spec.rb"
Task: "Unit spec for RenderClassifier in spec/unit/render_classifier_spec.rb"

# Then the extractor/locator extensions (parallel):
Task: "Extend RenderExtractor in lib/rails_openapi_generator/render_extractor.rb"
Task: "Extend ViewLocator in lib/rails_openapi_generator/view_locator.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (classification works)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: non-JSON endpoints are marked with content type, note, and tag
5. Demo the MVP

### Incremental Delivery

1. Setup + Foundational → classification ready
2. US1 → HTML/download endpoints visibly distinguished (MVP)
3. US2 → machine-readable vendor extensions
4. US3 → report counts
5. Polish → determinism, regression, docs

---

## Notes

- [P] = different files, no dependency on an incomplete task
- [US#] maps a task to its user story; [Test] marks a non-story test task
- All test specs MUST fail before their implementation task is started
- This feature is additive — JSON-endpoint output (features 001 & 002) must
  remain unchanged (FR-013, verified by T025)
- Commit after each task or logical group
