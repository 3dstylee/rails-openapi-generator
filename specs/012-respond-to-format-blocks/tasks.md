---
description: "Task list for respond_to Format Blocks"
---

# Tasks: respond_to Format Blocks

**Input**: Design documents from `/specs/012-respond-to-format-blocks/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Test tasks ARE included — Constitution Principle III (Test-First
Discipline) mandates every behavior change be covered by an automated test
written before/alongside implementation.

**Organization**: Tasks are grouped by user story (US1 P1, US2 P2). This
feature extends the existing gem (features 001–011). The scope is narrow:
detect `respond_to` blocks in `RenderExtractor`, add one optional field to
`RenderSite` (content_type), add one optional field to `ResponseEntry`
(content_types), and fan out multi-content-type entries in `DocumentBuilder`.

## Path Conventions

Existing Ruby gem: runtime code in `lib/rails_openapi_generator/`, tests in
`spec/` with the dummy Rails app under `spec/fixtures/dummy/`.

---

## Phase 1: Setup

**Purpose**: Version bump, dummy fixtures, and routes the feature needs

- [X] T001 Bump `VERSION` to `0.11.0` in `lib/rails_openapi_generator/version.rb` — `respond_to` block detection changes generated output (Constitution V)
- [X] T002 [P] Add `spec/fixtures/dummy/app/views/api/respond_to/index.json.jbuilder` with a typed jbuilder (e.g. `json.id 1; json.name "x"; json.metadata({})`)
- [X] T003 [P] Add `spec/fixtures/dummy/app/views/api/respond_to/index.html.erb` with minimal HTML (existence matters more than content)
- [X] T004 [P] Add `spec/fixtures/dummy/app/views/api/respond_to/json_only.json.jbuilder` (no sibling `.html.erb`)
- [X] T005 [P] Add `spec/fixtures/dummy/app/views/api/respond_to/html_only.html.erb` (no sibling `.json.jbuilder`)
- [X] T006 [P] Add `spec/fixtures/dummy/app/controllers/api/respond_to_controller.rb` exposing: (a) a GET `index` action doing `respond_to { |format| format.html { gon.push(gon_params) }; format.json }` (the motivating case — both formats); (b) a GET `json_only` action doing `respond_to { |format| format.json }` (only JSON view exists); (c) a GET `html_only` action doing `respond_to { |format| format.html }` (only HTML view exists); (d) a GET `explicit_json` action doing `respond_to { |format| format.json { render json: { id: 1, ok: true } }; format.html }` (inline `render json:` inside the block + default `.html.erb`); (e) a GET `unmapped` action doing `respond_to { |format| format.xml }` (unmapped format symbol — should be ignored)
- [X] T007 Add routes for the new actions in `spec/fixtures/dummy/config/routes.rb`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Detect `respond_to` blocks; thread `content_type` through the site → entry → emission pipeline.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Tests for the foundation ⚠️ (write first, must fail)

- [X] T008 [P] [Test] Extend `spec/unit/render_extractor_spec.rb` for `respond_to` detection: `respond_to { |format| format.json }` → one site with `content_type: "application/json"`, `template_name == SENTINEL_DEFAULT_VIEW`, `format_hint: :json`; `format.html` analogously → `content_type: "text/html"`, `format_hint: :html`; both formats → two sites, one per format; `format.json { render json: { id: 1 } }` → one site with `content_type: "application/json"`, schema from the inline render; `format.xml` and other unmapped symbols → no site; bare `format.X` outside a `respond_to` block (no enclosing `respond_to do |format|`) → no site; the block's parameter name is captured (so `respond_to do |fmt|; fmt.json; end` works the same way)
- [X] T009 [P] [Test] Extend `spec/unit/response_builder_spec.rb` for multi-content-type entry assembly: two sibling sites at the same status with distinct `content_type` markers produce one entry whose `content_types` is a Hash with both keys; same-status sites all sharing one `content_type` leave `content_types` nil (single-content-type, byte-identical to today); a JSON gate alongside a top-level `render json:` at the same status → `content_types` is set ONLY when an HTML gate is also present (single-content-type → fall back to today's `body`)
- [X] T010 [P] [Test] Extend `spec/unit/document_builder_spec.rb` asserting `entry_content` emits a multi-content-type `content:` map when `entry.content_types` is set, with keys sorted by content-type name ascending; the `text/html` value uses the existing `{type: string}` placeholder schema; when `content_types` is nil, today's per-kind emission path is taken (byte-identical regression)

### Implementation for the foundation

- [X] T011 Add `content_type` (String / nil) to `RenderSite` in `lib/rails_openapi_generator/render_extractor.rb`; default to nil. Define `RenderExtractor::FORMAT_CONTENT_TYPES = { json: "application/json", html: "text/html" }.freeze`. Add a `RenderExtractor::SENTINEL_DEFAULT_VIEW` constant (a non-empty marker string, e.g. `"__rog_default_view__"`) used as `template_name` for a bare format gate that needs the action's default view; the Generator replaces this sentinel during resolution
- [X] T012 Add `respond_to`-block detection in `lib/rails_openapi_generator/render_extractor.rb`: traverse the AST for `:method_add_block` nodes whose call is `respond_to` (an `:fcall` or `:method_add_arg` resolving to the identifier `"respond_to"`); capture the block param's name from `[:block_var, [:params, [[:@ident, NAME, ...]], ...]]`; walk the block body for `:call` (and `:method_add_block` wrapping `:call`) nodes whose receiver is `[:var_ref, [:@ident, NAME, ...]]` and whose method name is in `FORMAT_CONTENT_TYPES`; for each match, build a format-gate site (see T013)
- [X] T013 Add a `format_gate_site` builder in `lib/rails_openapi_generator/render_extractor.rb`: if the format call has a body block AND that block contains a render call (`render json:` / `render "..."` / `render :symbol` / `render template:` / `render action:` / `head`), recurse with the existing render-extraction rules and tag each resulting site with `content_type` = the gate's content type; otherwise emit one unresolved template-render site with `template_name: SENTINEL_DEFAULT_VIEW`, `format_hint: <format_symbol>`, `content_type: FORMAT_CONTENT_TYPES[<format_symbol>]`, and `explicit_status: nil`
- [X] T014 Extend `Generator#resolve_template_sites!` in `lib/rails_openapi_generator/generator.rb` to special-case sites whose `template_name == RenderExtractor::SENTINEL_DEFAULT_VIEW`: replace `template_name` with `"#{route.controller}/#{route.action}"` BEFORE calling `ViewLocator.locate_view` (then the existing resolution path handles JSON / HTML / no-view fallbacks; site's `content_type` is preserved across the swap)
- [X] T015 Add `content_types` (Hash / nil) to `ResponseEntry` in `lib/rails_openapi_generator/response.rb`; default to nil. Keep the `body` field for the single-content-type case
- [X] T016 Extend `ResponseBuilder#union_body` (or the surrounding entry-build path) in `lib/rails_openapi_generator/response_builder.rb` so that, when a status group contains sites with distinct `content_type` values, the entry is built with `content_types: { <content_type> => <union body for that content type>, ... }` and `body: nil`. Sites at the status whose `content_type` is nil (ordinary JSON renders, head sites, ordinary template-render sites) are folded into the `"application/json"` bucket per today's rules; sites with `content_type == "text/html"` are folded into a `text/html` bucket whose body is nil (matches today's HTML-page emission). When the group has only ONE distinct content type, leave `content_types` nil and use today's `body`-based path (SC-004)
- [X] T017 Extend `DocumentBuilder#entry_content` in `lib/rails_openapi_generator/document_builder.rb`: when `entry.content_types` is set, emit a `content:` map by iterating `content_types.sort.to_h` and building `{ <content_type> => { "schema" => <schema or {type: string} for text/html> } }`; when `entry.content_types` is nil, take today's per-kind emission path (regression check via T010)

**Checkpoint**: All foundational specs pass; an action without `respond_to` produces byte-identical output to `0.10.0`

---

## Phase 3: User Story 1 - Document an action with `format.html` and `format.json` (Priority: P1) 🎯 MVP

**Goal**: An action that uses `respond_to { |format| format.html { ... }; format.json }` is documented with a single 200 entry carrying both `application/json` (jbuilder schema) and `text/html` (placeholder schema) content types.

**Independent Test**: Generate against the dummy app and confirm the `index` operation's 200 entry has BOTH content types; the `json_only` and `html_only` operations each have just one content type.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T018 [P] [US1] Add `spec/integration/respond_to_format_blocks_spec.rb` asserting: the `index` operation has one response key `"200"` whose `content` map has both `"application/json"` and `"text/html"` keys (sorted alphabetical); the `application/json` schema is the resolved jbuilder shape (id, name, metadata properties); the `text/html` schema is `{ "type" => "string" }`; no "response shape could not be determined" warning is emitted
- [X] T019 [P] [US1] Extend `spec/integration/respond_to_format_blocks_spec.rb` for the `json_only` operation: response under `"200"` has `content` with ONLY `"application/json"` key (no empty `text/html`); for the `html_only` operation: response under `"200"` has `content` with ONLY `"text/html"` key, kind `:html_page` (vendor extension `x-renders-html: true`)

### Implementation for User Story 1

No new implementation — T011–T017 already deliver this story (format-gate detection + multi-content-type emission). T018–T019 verify end-to-end.

**Checkpoint**: MVP — the user's reported `respond_to { format.html ...; format.json }` shape is documented with both content types

---

## Phase 4: User Story 2 - Honor explicit renders inside format blocks (Priority: P2)

**Goal**: When a `format.X` call has a block with an explicit `render` inside, the inline render's status, schema, and content type override the default-view fallback for that format.

**Independent Test**: Generate against the dummy app and confirm the `explicit_json` operation's 200 entry has `application/json` content with the literal `{ id, ok }` schema (not the default `index.json.jbuilder` shape).

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T020 [P] [US2] Extend `spec/integration/respond_to_format_blocks_spec.rb` for the `explicit_json` operation: response under `"200"` has both `"application/json"` (with the literal `id` + `ok` schema from `render json: { id: 1, ok: true }`) and `"text/html"` (from the default `.html.erb`); assert the JSON schema is NOT the default `index.json.jbuilder` shape
- [X] T021 [P] [US2] Extend `spec/unit/render_extractor_spec.rb`: a `format.json { render json: { id: 1 } }` gate emits one site with `content_type: "application/json"` and `schema: { type: object, properties: { id: { type: integer } } }`; a `format.json { render json: { error: msg }, status: :unprocessable_entity }` emits a site at status 422 with the error schema and `content_type: "application/json"` — feature 010's status assignment continues to work

### Implementation for User Story 2

No new implementation — T013 (the `format_gate_site` builder) already recursively applies feature 010 + 011 detection rules to the gate's inline render block. T020–T021 verify the recursion is correct.

**Checkpoint**: Explicit renders inside `format.X` blocks override the default-view fallback; the gate's content type is preserved on the inline render's site

---

## Phase 5: Edge Cases (validation)

**Purpose**: Verify the spec's edge-case rules with focused integration assertions.

- [X] T022 [P] [US1] Extend `spec/integration/respond_to_format_blocks_spec.rb` for the `unmapped` operation (`format.xml`): the operation is documented as if no `respond_to` were present (today's fallback rules — likely undeterminable with a warning); the unmapped format symbol contributes no content type
- [X] T023 [P] [US1] Extend `spec/integration/respond_to_format_blocks_spec.rb` asserting determinism: two consecutive runs of `index` produce byte-identical `content` maps (including the alphabetical content-type order)

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Hardening, docs, determinism, regression

- [X] T024 [P] [Test] Extend `spec/integration/feature_001_regression_spec.rb` to assert SC-004: existing endpoints (users#index jbuilder, pages#show HTML, redirects, statuses, multi_status, template_renders) emit byte-identical responses to `0.10.0` — no entries gain a spurious `content_types` field; the multi-content-type emission path is NOT taken for them
- [X] T025 [P] [Test] Extend `spec/integration/determinism_spec.rb`: the both-formats `index` operation's `content` map is byte-identical across two runs, including content-type ordering and the jbuilder schema's property order
- [X] T026 [P] Update `README.md`'s response-detection section with a paragraph on `respond_to do |format| ... end` detection — the supported formats (`:json` and `:html`), the default-view fallback when the block has no inline render, the inline-render override, and the multi-content-type emission shape
- [X] T027 [P] Add a `0.11.0` entry to `CHANGELOG.md` describing `respond_to` format block detection, the `:json` / `:html` → content-type mapping, the multi-content-type emission, the silent-ignore rule for unmapped formats, and the SC-004 byte-identical guarantee for non-`respond_to` operations
- [X] T028 Update the `spec/integration/generate_all_endpoints_spec.rb` route-list assertion to include the new `respond_to` paths
- [X] T029 Run `quickstart.md` end-to-end against the dummy app and correct any discrepancies
- [X] T030 [P] Run RuboCop across the changed `lib/` files and resolve offenses

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately. T006/T007 depend on T002–T005 (views must exist before the controller refers to them)
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories. T008/T009/T010 (tests) before T011–T017 (implementation); T011 (struct fields) before T012/T013 (extractor uses them); T012/T013 before T014 (Generator resolves sentinel); T015 (entry field) before T016 (builder writes it); T016 before T017 (emitter reads it)
- **User Stories (Phase 3–5)**: All depend on Foundational completion
- **Polish (Phase 6)**: Depends on all targeted user stories

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational — the MVP, no new implementation (T018–T019 are verification only)
- **US2 (P2)**: Depends on US1 — the same foundation delivers it (T020–T021 are verification only)

### Within Each Phase

- Tests written first and failing before implementation (Constitution III)
- T011 (struct fields + constants) before any extractor work
- T012/T013 (extractor) before T014 (Generator sentinel resolution)
- T015 (entry field) before T016 (builder) before T017 (emitter)

### Parallel Opportunities

- Setup: T002–T005 parallel (different view files), T006 sequential after them, T007 sequential after T006
- Foundational tests: T008, T009, T010 parallel before T011–T017
- US1 verification: T018, T019 parallel
- US2 verification: T020, T021 parallel
- Edge cases: T022, T023 parallel
- Polish: T024, T025, T026, T027, T030 parallel; T028, T029 sequential at the end

---

## Parallel Example: Foundational tests (Phase 2)

```bash
Task: "Extend spec/unit/render_extractor_spec.rb for respond_to detection"
Task: "Extend spec/unit/response_builder_spec.rb for multi-content-type entry assembly"
Task: "Extend spec/unit/document_builder_spec.rb for multi-content-type emission"
```

All three must FAIL before T011–T017 are started.

## Parallel Example: User Story 1 integration

```bash
Task: "index operation shows both application/json and text/html content types"
Task: "json_only/html_only operations show only the matching single content type"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (version bump, views, controller, routes)
2. Complete Phase 2: Foundational (extractor detection + struct fields + builder/emitter wiring)
3. Complete Phase 3: User Story 1 (verification — assert both-formats / single-format operations)
4. **STOP and VALIDATE**: the `index` operation documents both `application/json` and `text/html` content under 200
5. Demo the MVP — covers the user's reported case

### Incremental Delivery

1. Setup + Foundational → `respond_to` blocks detected and emitted
2. US1 → both-formats documented (MVP — the reported case)
3. US2 → inline renders inside format blocks override the default-view path
4. Edge cases → unmapped formats and determinism verified
5. Polish → SC-004 regression, README, CHANGELOG, RuboCop

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (T011–T017 are tightly coupled)
2. Once Foundational is done:
   - Developer A: US1 verification + Polish T024 (regression)
   - Developer B: US2 verification
   - Developer C: Edge cases + Polish T026/T027 (docs)
3. Polish converges last

---

## Notes

- [P] = different files, no dependency on an incomplete task
- [US#] maps a task to its user story; [Test] marks a non-story test task
- All test specs MUST fail before their implementation task is started
- This feature is purely additive at the per-operation level for any
  endpoint that does NOT use `respond_to` — those operations MUST
  produce byte-identical output to `0.10.0` (SC-004, T024)
- `format.xml`, `format.csv`, `format.pdf`, `format.any`, `format.all`,
  dynamic dispatch (`format.send(:json)`), and `respond_to` without a
  block argument are deferred (FR-008 / FR-009); do not add them here
- Commit after each task or logical group
