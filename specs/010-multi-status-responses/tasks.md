---
description: "Task list for Multi-Status Responses"
---

# Tasks: Multi-Status Responses

**Input**: Design documents from `/specs/010-multi-status-responses/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Test tasks ARE included — Constitution Principle III (Test-First
Discipline) mandates every behavior change be covered by an automated test
written before/alongside implementation.

**Organization**: Tasks are grouped by user story (US1 P1, US2 P2, US3 P3).
This feature extends the existing gem (features 001–009). Phase 2 contains
the `Response` reshape — a single broad refactor that all user stories
build on; story tests are written first but their implementation tasks
share that one foundation.

## Path Conventions

Existing Ruby gem: runtime code in `lib/rails_openapi_generator/`, tests in
`spec/` with the dummy Rails app under `spec/fixtures/dummy/`.

---

## Phase 1: Setup

**Purpose**: Version bump, dummy fixtures, and routes the feature needs

- [X] T001 Bump `VERSION` to `0.9.0` in `lib/rails_openapi_generator/version.rb` — multi-status response detection changes generated output (Constitution V)
- [X] T002 [P] Add `spec/fixtures/dummy/app/controllers/concerns/auth_callback.rb` — a concern declaring `before_action :authenticate` with an `authenticate` private method that does `render json: { error: "unauthorized" }, status: :unauthorized`
- [X] T003 [P] Add `spec/fixtures/dummy/app/controllers/api/multi_status_controller.rb` with: (a) a PATCH `update` action doing a happy `render json: <method_call>` and a guard `render json: { error_messages: msgs }, status: :unprocessable_entity`; (b) a POST `dup_same` action doing two identical-shape `render json:` calls at the same status; (c) a POST `dup_distinct` action doing two literal `render json:` calls at the same status with distinct shapes; (d) a POST `head_and_render` action doing `head :ok` and `render json: { id: 1 }, status: :ok`; (e) a controller-level `before_action :require_admin, only: [:destroy]` whose `require_admin` does `render json: { error: "forbidden" }, status: :forbidden`; (f) a DELETE `destroy` action and a GET `show` action that both inherit the concern's `authenticate` before_action
- [X] T004 Add routes for the multi-status actions in `spec/fixtures/dummy/config/routes.rb`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Reshape `Response` into a multi-entry holder and broaden render-site extraction. Both pieces are touched by every user story.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Tests for the Response reshape ⚠️ (write first, must fail)

- [X] T005 [P] [Test] Extend `spec/unit/render_extractor_spec.rb` for `render_sites`: action with one render → one site with that status+schema; action with happy + error renders → two sites with distinct statuses; non-literal render → site with `schema: nil`; `head :ok` → site with `head: true`, `schema: nil`, `status: 200`; unknown `status:` symbol → site dropped; sites are returned in source order
- [X] T006 [P] [Test] Add `spec/unit/response_builder_spec.rb` cases for the entry-list shape: `Response.entries` is sorted by ascending status; single-entry construction for non-JSON kinds (redirect / html_page / file_download); fallback path produces `entries: [Entry(status: convention, body: nil)]` with `undeterminable: true`; per-status union table from `data-model.md` (0/1/N renders, head+render collapse, identical-schema dedup, distinct-schema `oneOf` sorted by canonical JSON ascending)
- [X] T007 [P] [Test] Extend `spec/unit/document_builder_spec.rb` asserting `responses` iterates `response.entries`: a one-entry Response emits the same single-key map as today; a two-entry Response emits two keys in numeric-ascending order; `oneOf` schemas serialize as `{"oneOf": [...]}` under `application/json`

### Implementation for the foundation

- [X] T008 Reshape `Response` in `lib/rails_openapi_generator/response.rb`: introduce `Response::Entry = Struct.new(:status, :body, keyword_init: true)`; replace the `status` and `body` fields with `entries: [Entry]`; keep `description`, `undeterminable`, `kind`, `page_reference`; keep the existing predicates (`undeterminable?`, `html_page?`, `file_download?`, `redirect?`)
- [X] T009 Extend `RenderResult` in `lib/rails_openapi_generator/render_extractor.rb` with `render_sites: Array<RenderSite>` (where `RenderSite = Struct.new(:status, :schema, :head, :source, keyword_init: true)`); collect a site for every `render json:` (status from explicit option or HTTP-method convention) and every `head` call across the action body; drop unmappable-status sites silently; keep all existing fields populated as today
- [X] T010 Rewrite `ResponseBuilder#build` in `lib/rails_openapi_generator/response_builder.rb` to construct `Response.entries` from `render_result.render_sites`: group by status; apply the union/dedup rules from `data-model.md` (0/1/N bodies, head + render collapse, identical-schema dedup, distinct-schema `oneOf` sorted by `JSON.generate` ascending); fall back to `entries: [Entry(status: HTTP-method-convention, body: view_schema || nil)]` with `undeterminable: true` when the JSON classification has no `render_sites` and no view schema; preserve single-entry construction for `:redirect`, `:html_page`, `:file_download`
- [X] T011 Update `DocumentBuilder#responses` and `DocumentBuilder#response_content` in `lib/rails_openapi_generator/document_builder.rb` to iterate `response.entries`: emit one key per entry, sorted ascending; `response_content` reads the entry's body for `:json` kinds (no `content` when body is nil) and continues to return the kind-specific content for `:html_page` / `:file_download` (one entry) and `nil` for `:redirect` (one entry); ensure `oneOf` schemas pass through unchanged
- [X] T012 Update `Generator#build_response` in `lib/rails_openapi_generator/generator.rb` so the "response shape could not be determined" warning fires only when `response.entries` is empty in the legacy sense — that is, when `response.undeterminable?` is true AND `response.kind != :redirect / :file_download / :html_page` (per FR-011)
- [X] T013 Update every other caller of `response.status` / `response.body` in `lib/` to read from `entries.first` instead (search: `lib/`); ensure the rake task / CLI continue to print the same summary lines they do today

**Checkpoint**: All foundational specs pass; the existing single-response output for features 002–009 is byte-identical (sanity-check by running the full suite at this point — feature-001 regression must still pass)

---

## Phase 3: User Story 1 - Document both the happy and error responses (Priority: P1) 🎯 MVP

**Goal**: A `PATCH` action with one happy `render json:` and one guard `render json:, status: :unprocessable_entity` is documented under two response status keys, each with its own body (or no body when the value is non-literal). Same-status collisions collapse per FR-004/FR-005.

**Independent Test**: Generate against the dummy app and confirm the `update` action shows both `200` and `422` keys; the `dup_same` action shows one entry; the `dup_distinct` action shows one entry with `oneOf`; the `head_and_render` action shows one entry with the render's body.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T014 [P] [US1] Add `spec/integration/multi_status_responses_spec.rb`: the `update` action has keys `["200", "422"]`, neither with `content`; no "response shape could not be determined" warning is emitted for it
- [X] T015 [P] [US1] Extend `spec/integration/multi_status_responses_spec.rb` for the `dup_same` action: one entry under the happy status with the (single) literal schema; **no** `oneOf` wrapping
- [X] T016 [P] [US1] Extend `spec/integration/multi_status_responses_spec.rb` for the `dup_distinct` action: one entry whose `application/json` schema is `{"oneOf": [<schema_a>, <schema_b>]}` sorted by canonical JSON ascending; assert byte-identical output across two generations
- [X] T017 [P] [US1] Extend `spec/integration/multi_status_responses_spec.rb` for the `head_and_render` action: one entry under `200` with the render's literal body; **no** `oneOf`; no extra body-less entry

### Implementation for User Story 1

No new implementation — T009 (render_sites for the action body) and T010 (union/oneOf assembly) already deliver this story. T014–T017 verify it end-to-end.

**Checkpoint**: MVP — multi-status JSON operations are documented; the user's reported `PATCH /api/v2/workflow/custom_maisokus/:id` shape works on the analogous fixture

---

## Phase 4: User Story 2 - Include renders reached through helper methods (Priority: P2)

**Goal**: A guard helper called from the action contributes its renders to the operation's response set, whether the helper is defined directly on the controller, on a parent, or in a concern mixed into the controller.

**Independent Test**: Generate against the dummy app and confirm an action that calls a helper doing `render json: { error: "..." }, status: :forbidden` produces a `403` entry; an action that does not call the helper does not.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T018 [P] [US2] Extend `spec/unit/render_extractor_spec.rb` (or add a new walker-coverage spec) asserting that `render_sites` includes renders reached through receiverless helper calls, recursively bounded by the walker depth; methods defined in a concern included into the controller are walked the same as direct methods; an unresolvable helper does not break the run
- [X] T019 [P] [US2] Extend `spec/integration/multi_status_responses_spec.rb`: add an action that calls a helper doing `render json: { error: "..." }, status: :forbidden`; assert the operation has a `403` entry with that schema; assert a sibling action that does NOT call the helper has no `403` entry

### Implementation for User Story 2

- [X] T020 [US2] Update `RenderExtractor.extract` in `lib/rails_openapi_generator/render_extractor.rb` to accept a `walker:` (the existing `ControllerMethodWalker`) and a `controller_class:`; collect renders/heads from every body returned by `walker.reachable_bodies(controller_class, action_node)`; tag each `RenderSite` with `source: :action` for the action body and `source: :helper` for everything reached through the walker
- [X] T021 [US2] Wire the walker into the `RenderExtractor` in `Generator#setup_pipeline` and `Generator#build_response` in `lib/rails_openapi_generator/generator.rb` so the walker / controller_class are threaded through to render extraction

**Checkpoint**: Helper-method renders contribute response entries; US1 still passes

---

## Phase 5: User Story 3 - Include renders reached through `before_action` callbacks (Priority: P3)

**Goal**: A `before_action` callback's renders are documented on the operations the callback applies to. `only:` / `except:` literal arrays are honored; non-literal conditionals fall back to "every action in the controller".

**Independent Test**: Generate against the dummy app and confirm: (a) the concern-included `authenticate` callback adds a `401` entry to every action in the controller; (b) the controller-level `before_action :require_admin, only: [:destroy]` adds a `403` entry to the `destroy` operation only.

### Tests for User Story 3 ⚠️ (write first, must fail)

- [X] T022 [P] [US3] Add `spec/unit/before_action_resolver_spec.rb` asserting: a controller with `before_action :foo` returns one callback for every action; a controller with `before_action :foo, only: [:update]` returns a callback whose `only` is `Set.new(%w[update])`; a controller with `before_action :foo, except: [:show]` returns a callback whose `except` is `Set.new(%w[show])`; an inherited callback (declared on a parent controller or in a concern) is returned with `only: nil, except: nil`; a callback whose method cannot be resolved is silently skipped (no exception, no warning)
- [X] T023 [P] [US3] Extend `spec/integration/multi_status_responses_spec.rb`: the `update` action has a `401` entry from the concern's `authenticate`; the `destroy` action has both `401` (from `authenticate`) AND `403` (from `require_admin`, `only: [:destroy]`); the `show` action has `401` but NOT `403`

### Implementation for User Story 3

- [X] T024 [US3] Add `lib/rails_openapi_generator/before_action_resolver.rb` exposing `BeforeActionResolver.new(method_resolver:, locator:).resolve(controller_class)` → `Array<BeforeActionCallback>` (`BeforeActionCallback = Struct.new(:method_name, :method_node, :only, :except, keyword_init: true)`): read `controller_class._process_action_callbacks(:process_action)` filtered to `kind == :before`; for each, read `instance_variable_get(:@filter)` to get the method symbol; resolve via `MethodResolver`; in a second pass, parse the controller's own source file with Ripper for `before_action` command calls and recover literal `only: [...]` / `except: [...]` arrays into matching callbacks; skip silently when the controller class cannot be loaded
- [X] T025 [US3] Add a `BeforeActionCallback#applies_to?(action_name)` predicate enforcing the `only` / `except` filter (`only`: `nil || only.include?(action_name)`; then `except`: `nil || !except.include?(action_name)`)
- [X] T026 [US3] Wire `BeforeActionResolver` into `Generator#setup_pipeline` and `Generator#build_response` in `lib/rails_openapi_generator/generator.rb` so for each route the resolver returns the callbacks applicable to that action; pass the callbacks into `RenderExtractor.extract` (or a sibling collector); each callback's `method_node` is walked the same as a helper body, contributing `RenderSite`s tagged `source: :before_action`
- [X] T027 [US3] Confirm — through an integration test, not a code change — that `:redirect` / `:file_download` / `:html_page` precedence is preserved: a controller with `before_action :authenticate` whose action is a redirect must still be documented as a redirect (single-entry, kind `:redirect`); the before_action's 401 entry does not leak in (FR-010)

**Checkpoint**: All three user stories are independently functional; the user's reported case (concern-included `authenticate` + happy/error renders in the action body) produces the full multi-status response set

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Hardening, docs, determinism, regression

- [X] T028 [P] [Test] Extend `spec/integration/feature_001_regression_spec.rb` to assert SC-005: every operation in the existing fixture (excluding the new `MultiStatusController`) emits the same `responses` map as in `0.8.0` — a one-key map under the same status with the same body; no `oneOf`; no extra entry from a passing before_action that wasn't there in 0.8.0
- [X] T029 [P] [Test] Extend `spec/integration/determinism_spec.rb`: the multi-status `dup_distinct` action's `oneOf` list and the multi-status `update` action's response keys are byte-identical across two consecutive runs
- [X] T030 [P] [Test] Extend `spec/integration/response_resilience_spec.rb`: an action with no render, no head, no redirect, no view template still emits the existing "response shape could not be determined" warning (the FR-011 fallback path)
- [X] T031 [P] Update `README.md` with a section on multi-status response detection (action body + helpers + before_action callbacks; `oneOf` union rule; out-of-scope rescue_from / exception-implied statuses)
- [X] T032 [P] Add a `0.9.0` entry to `CHANGELOG.md` describing multi-status response detection, the `Response` reshape (entries-based, internal), and the suppression of the "response shape could not be determined" warning for operations with at least one known status
- [X] T033 Run `quickstart.md` end-to-end against the dummy app and correct any discrepancies
- [X] T034 [P] Run RuboCop across the changed `lib/` files and resolve offenses
- [X] T035 Update the `spec/integration/generate_all_endpoints_spec.rb` route-list assertion to include the new multi-status paths

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories. The reshape touches every Response consumer; tests T005–T007 must drive the reshape before any user-story work can run
- **User Stories (Phase 3–5)**: All depend on Foundational completion
- **Polish (Phase 6)**: Depends on all targeted user stories

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational — the MVP, no new implementation (T014–T017 are verification only)
- **US2 (P2)**: Depends on US1 — needs walker integration (T020–T021)
- **US3 (P3)**: Depends on US2 — `before_action` resolution reuses the walker plumbing US2 puts in place (T024–T026)

### Within Each Phase

- Tests written first and failing before implementation (Constitution III)
- `Response` reshape (T008) before `RenderResult` extension (T009) — callers of the reshape need the new struct first
- `RenderResult.render_sites` (T009) before `ResponseBuilder` assembly (T010)
- `ResponseBuilder` (T010) before `DocumentBuilder` (T011) and `Generator` callsite fixup (T012, T013)
- T020/T021 (walker integration) must precede T024–T026 (before_action integration) — the latter reuses the same wiring

### Parallel Opportunities

- Setup: T002, T003, T004 parallel (different files)
- Foundational tests: T005, T006, T007 parallel before any T008–T013 implementation
- US1 verification: T014–T017 parallel (all in the same new integration file but distinct describe blocks — sequential within the file but ordered together)
- US2: T018/T019 in parallel before T020/T021
- US3: T022/T023 in parallel before T024/T025/T026/T027
- Polish: T028, T029, T030, T031, T032, T034 parallel

---

## Parallel Example: Foundational tests (Phase 2)

```bash
Task: "Add render_sites cases to spec/unit/render_extractor_spec.rb"
Task: "Add entry-list assertions to spec/unit/response_builder_spec.rb"
Task: "Add multi-entry emission cases to spec/unit/document_builder_spec.rb"
```

All three must FAIL before T008–T013 are executed.

## Parallel Example: User Story 1 integration

```bash
Task: "update action shows ['200', '422'] in spec/integration/multi_status_responses_spec.rb"
Task: "dup_same action shows one entry without oneOf"
Task: "dup_distinct action shows oneOf sorted by canonical JSON"
Task: "head_and_render action collapses head into the render's body"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (version bump, fixture controller, concern, routes)
2. Complete Phase 2: Foundational — the `Response` reshape is the big lift; once it's green, multi-status JSON for the action body is essentially done
3. Complete Phase 3: User Story 1 (verification only — assert the four scenarios)
4. **STOP and VALIDATE**: PATCH update action documents both 200 and 422; no warning; oneOf works; head+render collapses
5. Demo the MVP — already covers the user's reported case for action-body renders

### Incremental Delivery

1. Setup + Foundational → multi-entry Response shape available
2. US1 → action-body multi-status (MVP)
3. US2 → helper renders included (covers many real codebases' guard helpers)
4. US3 → before_action chain included (covers `authenticate` / `require_admin` patterns)
5. Polish → regression, determinism, docs

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (the reshape is one logical change, hard to parallelize across people)
2. Once Foundational is done:
   - Developer A: US1 verification + Polish T028 (regression)
   - Developer B: US2 walker integration
   - Developer C: US3 before_action resolver + tests
3. Polish converges last

---

## Notes

- [P] = different files, no dependency on an incomplete task
- [US#] maps a task to its user story; [Test] marks a non-story test task
- All test specs MUST fail before their implementation task is started
- This feature reshapes `Response` internally (entries-based). Operations
  that produced a single-entry Response in 0.8.0 MUST produce a byte-
  identical OpenAPI map in 0.9.0 (SC-005, T028)
- `rescue_from` handlers and exception-implied statuses (Pundit
  `authorize`, AR `find!`) are deferred to a future feature (FR-009);
  do not add them here
- Commit after each task or logical group
