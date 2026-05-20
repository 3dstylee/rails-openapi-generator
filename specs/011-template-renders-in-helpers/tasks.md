---
description: "Task list for Template Renders in Helpers"
---

# Tasks: Template Renders in Helpers

**Input**: Design documents from `/specs/011-template-renders-in-helpers/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Test tasks ARE included — Constitution Principle III (Test-First
Discipline) mandates every behavior change be covered by an automated test
written before/alongside implementation.

**Organization**: Tasks are grouped by user story (US1 P1, US2 P2, US3 P3).
This feature extends the existing gem (features 001–010). The scope is
narrow: extend `RenderSite` with template-render fields, gate
`ViewLocator` on a `format_hint:`, and add one post-processing pass in
the Generator. No new top-level class.

## Path Conventions

Existing Ruby gem: runtime code in `lib/rails_openapi_generator/`, tests in
`spec/` with the dummy Rails app under `spec/fixtures/dummy/`.

---

## Phase 1: Setup

**Purpose**: Version bump, dummy fixtures, and routes the feature needs

- [X] T001 Bump `VERSION` to `0.10.0` in `lib/rails_openapi_generator/version.rb` — template-render-in-helper detection changes generated output (Constitution V)
- [X] T002 [P] Add `spec/fixtures/dummy/app/views/api/template_renders/show.json.jbuilder` with a small typed jbuilder (e.g. `json.id 1; json.status "ok"; json.assignments []`)
- [X] T003 [P] Add `spec/fixtures/dummy/app/views/api/template_renders/show.html.erb` containing minimal valid HTML (a placeholder; existence matters more than content)
- [X] T004 [P] Add `spec/fixtures/dummy/app/views/api/template_renders/forbidden.json.jbuilder` for the before_action callback case (e.g. `json.error "forbidden"; json.reason "..."`)
- [X] T005 [P] Add `spec/fixtures/dummy/app/controllers/api/template_renders_controller.rb` exposing: (a) a PUT `update` action whose body is `return render_error unless params[:ok]; render_show`, with private helpers `render_show` (does `render "api/template_renders/show", formats: :json, handlers: [:jbuilder]`) and `render_error` (does `render json: { message: "..." }, status: :conflict`); (b) a GET `as_html` action whose helper does `render "api/template_renders/show", formats: :html`; (c) a GET `missing` action whose helper does `render "api/template_renders/no_such_view"`; (d) a DELETE `destroy` action that inherits a controller-level `before_action :forbid_unless_admin` whose method does `render "api/template_renders/forbidden", status: :forbidden, formats: :json`
- [X] T006 Add routes for the new actions in `spec/fixtures/dummy/config/routes.rb`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Extend the render-site model with template-render fields and gate ViewLocator on a format hint.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Tests for the foundation ⚠️ (write first, must fail)

- [X] T007 [P] [Test] Extend `spec/unit/render_extractor_spec.rb` for template-render sites: `render "path"` → site with `template_name: "path"`, `format_hint: nil`; `render :symbol` → site with `template_name: "symbol"`; `render template: "x"` / `render action: :y` → site with the corresponding template name; `render "x", formats: :json` → site with `format_hint: :json`; `render "x", formats: [:json, :html]` → site with `format_hint: [:json, :html]`; non-literal `formats:` value → site with `format_hint: nil`; template sites collected from helper bodies (via `collect_sites`) carry `source: :helper`
- [X] T008 [P] [Test] Extend `spec/unit/view_locator_spec.rb` for `format_hint:` resolution: `format_hint: :json` returns the `.json.jbuilder` view when present, returns `nil` when only `.html.*` exists; `format_hint: :html` returns the `.html.*` view, returns `nil` when only `.json.jbuilder` exists; `format_hint: [:json, :html]` tries JSON first then HTML; `format_hint: nil` behaves identically to today's "prefer JSON" lookup (regression case)

### Implementation for the foundation

- [X] T009 Add `template_name`, `format_hint`, and `kind_hint` fields to `RenderSite` in `lib/rails_openapi_generator/render_extractor.rb`; default all three to nil; keep all existing fields (`explicit_status`, `schema`, `head`, `source`) and helpers (`head?`) unchanged
- [X] T010 Extend `RenderExtractor#json_site` (or add a sibling `template_site` builder) in `lib/rails_openapi_generator/render_extractor.rb` so that for every `render` call with no `:json`/`:html` option and either a String/Symbol positional, a `template:` option, or an `action:` option, the extractor emits a template site with `template_name` recovered (via the existing `explicit_template_name` logic) and `format_hint` from `LiteralEvaluator.evaluate(options[:formats])` when that value is a Symbol or non-empty Array<Symbol>; non-literal values leave `format_hint` nil
- [X] T011 Extend `ViewLocator#locate_view` in `lib/rails_openapi_generator/view_locator.rb` to accept a `format_hint:` keyword (Symbol, Array<Symbol>, or nil); when set to `:json`, only consider `.json.jbuilder` matches; when set to `:html`, only consider `.html.*` matches; when an Array, try each format in order; when nil, behave exactly as today (prefer JSON). Return `nil` when no candidate matches the requested hint
- [X] T012 Add `Generator#resolve_template_sites(sites, route)` in `lib/rails_openapi_generator/generator.rb` that walks the site list and, for each site with a non-nil `template_name`, calls `@view_locator.locate_view(route, site.template_name, format_hint: site.format_hint)`, then: (a) when the match is a `.json.jbuilder`, replaces the site with a JSON site (`schema: @jbuilder_parser.parse(match.path)`, `template_name: nil`, `format_hint: nil`); (b) when the match is `.html.*`, replaces the site with an HTML-template site (`schema: nil`, `kind_hint: :html_page`, `template_name: nil`, `format_hint: nil`); (c) when no view matches, replaces the site with a body-less JSON site (`schema: nil`, `template_name: nil`, `format_hint: nil`)
- [X] T013 Wire `resolve_template_sites` into `Generator#build_response` in `lib/rails_openapi_generator/generator.rb`: after `collect_extra_sites` combines action + helper + before_action sites, run the post-processing pass so the site list passed to `ResponseBuilder.build` is uniform (no unresolved template sites remain). Also resolve template sites inside `render_result.render_sites` before they reach `ResponseBuilder`
- [X] T014 Extend `ResponseBuilder#union_body` (or a sibling helper) in `lib/rails_openapi_generator/response_builder.rb` so that HTML-template sites (`kind_hint: :html_page`) at the same status as any JSON site (any site whose `kind_hint != :html_page` and that is not body-less by way of `head: true` alone) are dropped from the union (FR-006). When every site at every status is an HTML-template, build a single-entry HTML-page Response (today's behavior — body nil, `kind: :html_page`, `page_reference: <template_name from the single site>`)

**Checkpoint**: The full existing suite still passes; template-render sites for the action body resolve to schema/HTML/body-less correctly

---

## Phase 3: User Story 1 - Document a happy template render that lives in a helper (Priority: P1) 🎯 MVP

**Goal**: An action whose helper does `render "...", formats: :json` is documented with the happy-status entry whose body is the resolved jbuilder schema, alongside any other entries the action body contributes (e.g. an error JSON render).

**Independent Test**: Generate against the dummy app and confirm the `update` operation shows `200` (with the jbuilder schema from `show.json.jbuilder`) and `409` (with the action-body's error render schema).

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T015 [P] [US1] Add `spec/integration/template_renders_in_helpers_spec.rb` asserting: the `update` operation's `responses` keys contain `"200"` and `"409"`; the `200` entry's `application/json` schema includes the literal jbuilder properties (`id`, `status`, `assignments`); the `409` entry's `application/json` schema includes the `message` key; no "response shape could not be determined" warning is emitted for the route
- [X] T016 [P] [US1] Extend `spec/integration/template_renders_in_helpers_spec.rb` asserting that for the `update` operation, the OpenAPI document validates against the OpenAPI 3.1 schema (smoke check the new shapes don't break validation)

### Implementation for User Story 1

No new implementation — T009–T014 (template-site extraction + format-hint resolution + post-processing + union/drop rules) already deliver this story. T015–T016 verify it end-to-end.

**Checkpoint**: MVP — the user's reported `PATCH /api/v2/workflow/custom_maisokus/:id` shape works on the analogous fixture (`update` shows both 200 from the helper template render and 409 from the action-body error render)

---

## Phase 4: User Story 2 - Honor `formats: :html` for HTML-page classification (Priority: P2)

**Goal**: An action whose helper does `render "...", formats: :html` is documented as `:html_page` (with `text/html` content type and the `x-renders-html` vendor extension), not as JSON, when no other renders contribute.

**Independent Test**: Generate against the dummy app and confirm the `as_html` operation has `kind: :html_page` (vendor extension present, `text/html` content), and the response is a single entry.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T017 [P] [US2] Extend `spec/integration/template_renders_in_helpers_spec.rb` asserting: the `as_html` operation has `x-renders-html: true`, its single response under `"200"` carries `text/html` content (not `application/json`), and `response_kind_count` for `:html_page` reflects the new endpoint
- [X] T018 [P] [US2] Extend `spec/unit/render_classifier_spec.rb` (or `spec/unit/response_builder_spec.rb`, whichever owns the kind-selection logic) asserting that a site list containing only HTML-template sites at exactly one status produces a single-entry Response with `kind: :html_page`; a site list mixing HTML-template at status X and a JSON site at status Y produces a multi-entry Response with `kind: :json` (per research R5)

### Implementation for User Story 2

- [X] T019 [US2] If the kind-selection logic does not already pick `:html_page` for the single-status all-HTML-template case (T014 covers the response-body collapse but kind selection may need a separate branch in `ResponseBuilder#build`), extend that branch in `lib/rails_openapi_generator/response_builder.rb`: when every site is HTML-template at exactly one status, return a single-entry Response with `kind: :html_page` and `page_reference` set to the template name of the (deduplicated) site; otherwise (mixed HTML + JSON) emit `kind: :json` multi-entry per the union table

**Checkpoint**: Explicit `formats: :html` is honored; an action that only renders HTML through a helper documents as `:html_page`; an action that mixes HTML helper render + a JSON guard render documents as `:json` (multi-entry)

---

## Phase 5: User Story 3 - Template renders in `before_action` callbacks (Priority: P3)

**Goal**: A `before_action` callback that does a template render contributes an entry to operations the callback applies to, resolved by the same view-locator + format-hint pipeline.

**Independent Test**: Generate against the dummy app and confirm the `destroy` operation has a `403` entry whose body is the resolved `forbidden.json.jbuilder` schema, plus its existing `204` head response.

### Tests for User Story 3 ⚠️ (write first, must fail)

- [X] T020 [P] [US3] Extend `spec/integration/template_renders_in_helpers_spec.rb` asserting: the `destroy` operation has both `204` (from the action's `head :no_content`) and `403` (from the before_action's template render); the `403` entry's body matches the resolved `forbidden.json.jbuilder` schema; `only:` / `except:` filtering on the callback continues to work (action excluded from the filter does not get the 403 entry)

### Implementation for User Story 3

No new implementation — T013 (Generator wiring) already invokes the same `resolve_template_sites` pass on before_action-derived sites because `Generator#collect_extra_sites` (from feature 010) returns the before_action sites alongside helper sites. T020 verifies the end-to-end behavior.

**Checkpoint**: All three user stories are independently functional; the multi-status feature now sees template renders the same way it sees JSON renders

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Hardening, docs, determinism, regression

- [X] T021 [P] [Test] Extend `spec/integration/feature_001_regression_spec.rb` to assert SC-004: existing single-render endpoints (the dummy app's pre-existing jbuilder-view endpoints and `Api::PagesController` HTML pages) emit byte-identical responses to `0.9.0` — same keys, same schemas, same `x-` marks, no spurious extra entries
- [X] T022 [P] [Test] Extend `spec/integration/determinism_spec.rb`: the new `update` operation's `responses` keys and the `200` jbuilder schema are byte-identical across two consecutive runs; if the integration spec exercises any `oneOf` case introduced by mixing a template render and a JSON render at the same status, that `oneOf` order is byte-identical too
- [X] T023 [P] [Test] Extend `spec/integration/response_resilience_spec.rb` (or the new `template_renders_in_helpers_spec.rb`): an action whose helper does `render "no_such_view"` (no `.json.jbuilder` and no `.html.*` exist) produces a single entry under the HTTP-method convention with no `content` key, AND no `"response shape could not be determined"` warning (the status is known, the body is unknown)
- [X] T024 [P] Update `README.md`'s response-detection section with a paragraph on template renders reached through helpers and before_action callbacks, including the `formats:` option honoring (literal Symbol / literal Array; non-literal ignored) and the JSON-wins-at-same-status rule
- [X] T025 [P] Add a `0.10.0` entry to `CHANGELOG.md` describing template-render-in-helper detection, the `formats:` hint honoring, the body-less fallback for missing views, and the SC-004 byte-identical guarantee for existing single-render endpoints
- [X] T026 Update the `spec/integration/generate_all_endpoints_spec.rb` route-list assertion to include the new `template_renders` paths
- [X] T027 Run `quickstart.md` end-to-end against the dummy app and correct any discrepancies
- [X] T028 [P] Run RuboCop across the changed `lib/` files and resolve offenses

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories. T007/T008 (tests) before T009–T014 (implementation); T009 before T010 (extractor builds on the new struct fields); T011 before T012 (Generator post-processing calls ViewLocator with format_hint:); T012 before T013 (wiring uses the new method); T014 finalizes union-drop rules
- **User Stories (Phase 3–5)**: All depend on Foundational completion
- **Polish (Phase 6)**: Depends on all targeted user stories

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational — the MVP, no new implementation (T015–T016 are verification only)
- **US2 (P2)**: Depends on US1 — T017/T018 (tests) before T019 (kind-selection refinement, if needed)
- **US3 (P3)**: Depends on US2 — no new implementation; T020 verifies the existing Generator wiring already picks up before_action template renders

### Within Each Phase

- Tests written first and failing before implementation (Constitution III)
- `RenderSite` field addition (T009) before extractor extension (T010)
- `ViewLocator` format_hint (T011) before Generator post-processing (T012)
- Generator post-processing (T012) before wiring (T013)
- T014 (union-drop rule for HTML at same status as JSON) lands last in Phase 2

### Parallel Opportunities

- Setup: T002, T003, T004, T005 parallel (all different files); T006 sequential (depends on T005's controller)
- Foundational tests: T007 and T008 parallel before T009–T014
- US1: T015 and T016 parallel before considering the story done (no impl tasks)
- US2: T017 and T018 parallel before T019
- Polish: T021, T022, T023, T024, T025, T028 parallel

---

## Parallel Example: Foundational tests (Phase 2)

```bash
Task: "Extend spec/unit/render_extractor_spec.rb for template-render sites"
Task: "Extend spec/unit/view_locator_spec.rb for format_hint: resolution"
```

Both must FAIL before T009–T014 are started.

## Parallel Example: User Story 1 integration

```bash
Task: "update operation shows 200 (jbuilder schema) and 409 in spec/integration/template_renders_in_helpers_spec.rb"
Task: "the document still passes OpenAPI 3.1 validation with the new shapes"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (version bump, fixture views + controller + routes)
2. Complete Phase 2: Foundational (extractor + view-locator + Generator post-processing)
3. Complete Phase 3: User Story 1 (verification only — assert the `update` operation's two entries)
4. **STOP and VALIDATE**: the `update` action documents both 200 (from the helper template render) and 409 (from the action-body error render)
5. Demo the MVP — already covers the user's reported `custom_maisokus#update` case

### Incremental Delivery

1. Setup + Foundational → template renders detected and resolved
2. US1 → happy template render in helper documented (MVP)
3. US2 → `formats: :html` honored (HTML-page classification preserved)
4. US3 → before_action template renders contribute too
5. Polish → SC-004 regression, determinism, docs

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (T009 / T011 / T014 are tightly coupled)
2. Once Foundational is done:
   - Developer A: US1 integration verification + Polish T021 (regression)
   - Developer B: US2 (kind selection refinement)
   - Developer C: US3 verification + before_action wiring sanity check
3. Polish converges last

---

## Notes

- [P] = different files, no dependency on an incomplete task
- [US#] maps a task to its user story; [Test] marks a non-story test task
- All test specs MUST fail before their implementation task is started
- This feature is purely additive at the per-operation level for any
  endpoint whose only render today is a single action-body template
  render (HTML pages, jbuilder JSON views) — those operations MUST
  produce byte-identical output to `0.9.0` (SC-004, T021)
- `format.json { render ... }` inside `respond_to`, dynamic dispatch,
  non-literal `formats:` values, `render partial:`, and bare-status-
  symbol renders (`render :ok`) are deferred (FR-009); do not add
  them here
- Commit after each task or logical group
