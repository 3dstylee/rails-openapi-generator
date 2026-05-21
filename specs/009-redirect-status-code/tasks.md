---
description: "Task list for Redirect Response Status Code"
---

# Tasks: Redirect Response Status Code

**Input**: Design documents from `/specs/009-redirect-status-code/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Test tasks ARE included — Constitution Principle III (Test-First
Discipline) mandates every behavior change be covered by an automated test
written before/alongside implementation.

**Organization**: Tasks are grouped by user story (US1 P1, US2 P2, US3 P3).
This feature extends the existing gem (features 001–008).

## Path Conventions

Existing Ruby gem: runtime code in `lib/rails_openapi_generator/`, tests in
`spec/` with the dummy Rails app under `spec/fixtures/dummy/`.

---

## Phase 1: Setup

**Purpose**: Version bump and test fixtures the feature needs

- [X] T001 Bump `VERSION` to `0.8.0` in `lib/rails_openapi_generator/version.rb` — redirect detection changes generated output (Constitution V)
- [X] T002 [P] Add `spec/fixtures/dummy/app/controllers/api/redirects_controller.rb` with: a POST action that does a bare `redirect_to` (default 302); a POST action with `redirect_to …, status: :see_other` (303); a GET action with `redirect_to …, status: 301`; a POST action with `redirect_back_or_to` (302); a POST action with both `render json: {…}` and a fallback `redirect_to` (asserting JSON-precedence)
- [X] T003 Add routes for the redirects-controller actions in `spec/fixtures/dummy/config/routes.rb`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Extract the redirect status from the action AST

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 [P] [Test] Extend `spec/unit/render_extractor_spec.rb` for `redirect_status`: bare `redirect_to` → 302; `status: :see_other` → 303; `status: 301` → 301; `redirect_back` / `redirect_back_or_to` → 302; non-3xx `status:` → nil; unknown status symbol → 302; multiple redirects → last wins; no redirect call → nil
- [X] T005 Add `redirect_status` to `RenderResult` in `lib/rails_openapi_generator/render_extractor.rb`; detect `redirect_to` / `redirect_back` / `redirect_back_or_to` calls; resolve `status:` option via existing `STATUS_CODES` / `status_code` helper; accept only `300..399` (default `302` when no `status:` is set or its symbol is unmapped); keep the last happy redirect in source order

**Checkpoint**: `RenderExtractor` reports `redirect_status`; existing feature-001–008 specs still load

---

## Phase 3: User Story 1 - Document a redirect with its actual status code (Priority: P1) 🎯 MVP

**Goal**: A redirecting action's success response is filed under `302` (or its explicit 3xx status) with no body, and no "response shape could not be determined" warning is emitted for it.

**Independent Test**: Generate against the dummy app and confirm the bare-redirect POST is documented under `302` with no `content`, and no warning is emitted for that route.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T006 [P] [US1] Extend `spec/unit/render_classifier_spec.rb` asserting a `RenderResult` carrying only `redirect_status` (no JSON / file / html / view signals) classifies as `:redirect`; if a JSON / file / html / view signal is also present, the existing kind still wins
- [X] T007 [P] [US1] Extend `spec/unit/response_builder_spec.rb` asserting a `:redirect` classification builds a `Response` with `status` equal to `render_result.redirect_status`, `body` nil, `kind` `:redirect`, and `undeterminable` false
- [X] T008 [P] [US1] Extend `spec/unit/document_builder_spec.rb` asserting a `:redirect` `Response` emits the operation's response under the redirect's status with `description: "Successful response"` and **no** `content` key
- [X] T009 [P] [US1] Add `spec/integration/redirect_response_spec.rb`: the bare-redirect POST appears under `'302'` with no `content`; the `GenerationReport.warnings` list contains no "response shape could not be determined" entry for that route

### Implementation for User Story 1

- [X] T010 [US1] Add `:redirect` to `RenderClassifier` in `lib/rails_openapi_generator/render_classifier.rb`: after JSON / file_download / inline html / view-lookup precedence and before the wrapper-download / undeterminable fallback, classify as `:redirect` when `render_result.redirect_status` is present
- [X] T011 [US1] Handle the `:redirect` kind in `ResponseBuilder#build` in `lib/rails_openapi_generator/response_builder.rb`: emit `Response.new(status: render_result.redirect_status, kind: :redirect)` — no body, not undeterminable
- [X] T012 [US1] Add `:redirect` to `Response` in `lib/rails_openapi_generator/response.rb`: a `redirect?` predicate symmetric with `html_page?` / `file_download?`
- [X] T013 [US1] Extend `DocumentBuilder#response_content` in `lib/rails_openapi_generator/document_builder.rb` so a `:redirect` `Response` emits no `content` (mirroring the `html_page` / `file_download` content-mapping pattern)

**Checkpoint**: MVP — a redirecting POST is documented under the correct redirect status with no body and no spurious warning

---

## Phase 4: User Story 2 - Honor an explicit redirect status (Priority: P2)

**Goal**: When the `redirect_to` call carries a 3xx `status:` option, the documented status matches that option (not `302`).

**Independent Test**: Generate against the dummy app and confirm the `:see_other` POST is documented under `'303'`, and the `status: 301` GET is documented under `'301'`.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T014 [P] [US2] Extend `spec/integration/redirect_response_spec.rb` asserting the `:see_other` POST → `'303'`, the integer `status: 301` GET → `'301'`, and the `redirect_back_or_to` POST → `'302'` (all body-less)

### Implementation for User Story 2

No new implementation — T005 (which honors `status:` via `STATUS_CODES`) and T010–T013 (which surface the redirect status into the `Response`) already deliver this story. T014 verifies the behavior end-to-end.

**Checkpoint**: Explicit 3xx statuses are honored; US1 still passes

---

## Phase 5: User Story 3 - Redirect classifies, doesn't fall through (Priority: P3)

**Goal**: A redirecting action no longer reaches the `:undeterminable` fallback or emits the "response shape could not be determined" warning; JSON-render precedence over `redirect_to` is preserved.

**Independent Test**: Generate against the dummy app and confirm (a) no redirect action emits the "response shape could not be determined" warning, and (b) the action that has both `render json:` and `redirect_to` is documented as JSON, not as a redirect.

### Tests for User Story 3 ⚠️ (write first, must fail)

- [X] T015 [P] [US3] Extend `spec/integration/redirect_response_spec.rb` asserting: the mixed `render json:` + `redirect_to` action is documented as JSON (status from the JSON-render rules, `application/json` body) — not as a redirect; and the redirect actions emit no "response shape could not be determined" warning
- [X] T016 [P] [US3] Extend `spec/integration/response_resilience_spec.rb` (or add to `redirect_response_spec.rb`) asserting that an action with no render and no redirect still emits the existing "response shape could not be determined" warning — this regression must hold

### Implementation for User Story 3

No new implementation — the classifier precedence in T010 already enforces JSON-wins; T011's body-less, non-undeterminable `Response` removes the warning trigger.

**Checkpoint**: All three user stories are independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Hardening, description note, docs, and finalization

- [X] T017 [US1] Extend `OperationBuilder#page_note` in `lib/rails_openapi_generator/operation_builder.rb` to add `_Redirects to another URL._` for a `:redirect` response (mirroring the existing `html_page` / `file_download` notes); cover with `spec/unit/operation_builder_spec.rb` (or the appropriate existing spec) if a unit spec exists, and with the description assertion in `spec/integration/redirect_response_spec.rb`
- [X] T018 [P] [Test] Regression: extend `spec/integration/feature_001_regression_spec.rb` to assert that non-redirecting endpoints' status, body, kind, tags, and `x-` marks are unchanged (FR-010)
- [X] T019 [P] [Test] Extend `spec/integration/determinism_spec.rb` to assert redirect operations are byte-identical across runs (FR-011)
- [X] T020 [P] Update `README.md` with a note on redirect status-code detection
- [X] T021 [P] Add a `0.8.0` entry to `CHANGELOG.md` describing redirect response detection (default 302, explicit 3xx, body-less, suppresses the "response shape could not be determined" warning)
- [X] T022 Run `quickstart.md` end-to-end against the dummy app and correct any discrepancies
- [X] T023 [P] Run RuboCop across the changed `lib/` files and resolve offenses

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **User Stories (Phase 3–5)**: All depend on Foundational completion
- **Polish (Phase 6)**: Depends on all targeted user stories

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational — the MVP
- **US2 (P2)**: Depends on US1 — no new implementation; verifies T005 + T010–T013 honor the explicit 3xx status
- **US3 (P3)**: Depends on US1 — no new implementation; verifies the classifier precedence (T010) and the body-less, non-undeterminable redirect `Response` (T011)

### Within Each User Story

- Tests written first and failing before implementation (Constitution III)
- `RenderExtractor` (T005) before `RenderClassifier` (T010) and `ResponseBuilder` (T011)
- `Response` predicate (T012) and `DocumentBuilder` branch (T013) can land in parallel after T011

### Parallel Opportunities

- Setup: T002 in parallel with T001
- Foundational: tests T004 before T005
- US1: tests T006/T007/T008/T009 in parallel before implementation; implementation T012/T013 in parallel after T011
- Polish: T018, T019, T020, T021, T023 in parallel

---

## Parallel Example: User Story 1

```bash
# Launch all US1 unit + integration tests together (they must fail first):
Task: "Extend spec/unit/render_classifier_spec.rb for :redirect classification"
Task: "Extend spec/unit/response_builder_spec.rb for the :redirect Response shape"
Task: "Extend spec/unit/document_builder_spec.rb asserting no content for a redirect"
Task: "Add spec/integration/redirect_response_spec.rb asserting the bare 302 case"

# Launch the parallelizable US1 implementation tasks together (after T011):
Task: "Add redirect? predicate to lib/rails_openapi_generator/response.rb"
Task: "Add :redirect branch to DocumentBuilder#response_content"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (version bump, fixture controller, routes)
2. Complete Phase 2: Foundational (`RenderExtractor` reports `redirect_status`)
3. Complete Phase 3: User Story 1 (classifier + builder + document emission)
4. **STOP and VALIDATE**: a bare-`redirect_to` POST is documented under `'302'` with no body and no warning
5. Demo the MVP

### Incremental Delivery

1. Setup + Foundational → redirect status available
2. US1 → bare redirects documented correctly (MVP)
3. US2 → explicit 3xx statuses honored
4. US3 → precedence with JSON-render verified, warning gone for redirects
5. Polish → description note, regression, determinism, docs

---

## Notes

- [P] = different files, no dependency on an incomplete task
- [US#] maps a task to its user story; [Test] marks a non-story test task
- All test specs MUST fail before their implementation task is started
- This feature changes only the documented response for actions whose only
  happy-path signal is a `redirect_to` (or `redirect_back` /
  `redirect_back_or_to`). Endpoints classified as JSON / file_download /
  html_page / `head` must stay byte-identical (FR-010, T018)
- Commit after each task or logical group
