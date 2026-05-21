---
description: "Task list for jbuilder Partials & case/when Branches"
---

# Tasks: jbuilder Partials & case/when Branches

**Input**: Design documents from `/specs/016-jbuilder-partials-and-case-branches/`

**Prerequisites**: plan.md, spec.md, research.md

**Tests**: Test tasks ARE included — Constitution Principle III
(Test-First Discipline) mandates every behavior change be covered
by an automated test written before/alongside implementation.

**Organization**: Two user stories (US1 P1 partial resolution,
US2 P2 case/when merging). One-file production change in
`lib/rails_openapi_generator/jbuilder_parser.rb` plus fixture
additions and test coverage.

## Path Conventions

Existing Ruby gem: runtime code in `lib/rails_openapi_generator/`,
tests in `spec/` with the dummy Rails app under
`spec/fixtures/dummy/`.

---

## Phase 1: Setup

**Purpose**: Version bump and fixture additions

- [X] T001 Bump `VERSION` to `0.16.0` in `lib/rails_openapi_generator/version.rb` — partial resolution + case/when merge change generated schema shape (Constitution V)
- [X] T002 [P] Add `spec/fixtures/dummy/app/views/api/activity_logs/_activity_log.json.jbuilder` with a small typed jbuilder: `json.id 1; json.message "hello"; json.created_at "2026-01-01"` — the partial used by the new index template
- [X] T003 [P] Add `spec/fixtures/dummy/app/views/api/activity_logs/index.json.jbuilder` exercising the `json.<key> @collection, partial: "name", as: :name` form for FOUR sibling keys (mirroring the user's reported pattern): `json.today_logs @c, partial: "activity_logs/activity_log", as: :activity_log; json.week_logs @c, partial: "activity_logs/activity_log", as: :activity_log; json.month_logs @c, partial: "activity_logs/activity_log", as: :activity_log; json.old_logs @c, partial: "activity_logs/activity_log", as: :activity_log`
- [X] T004 [P] Add `spec/fixtures/dummy/app/views/api/case_branches/show.json.jbuilder` exercising the `case x; when 1; json.a 1; when 2; json.b 2; else; json.c 3; end` shape — distinct keys per branch to make the union obvious in the assertion
- [X] T005 [P] Add `spec/fixtures/dummy/app/controllers/api/activity_logs_controller.rb` with a GET `index` action that has no inline render (so the jbuilder view is the response source). Then add `spec/fixtures/dummy/app/controllers/api/case_branches_controller.rb` with a GET `show` action, no inline render
- [X] T006 Add routes for the new actions in `spec/fixtures/dummy/config/routes.rb`
- [X] T007 Update the `spec/integration/generate_all_endpoints_spec.rb` route-list assertion to include the new paths

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Add unit tests for the two AST cases. Then make them pass via the two narrow production-code changes.

### Tests for the foundation ⚠️ (write first, must fail)

- [X] T008 [Test] Extend `spec/unit/jbuilder_parser_spec.rb` for the `json.<key>` partial form: (a) `json.today_logs @c, partial: "activity_log", as: :activity_log` resolves the partial and emits `{type: array, items: <partial schema>}`; (b) `json.user partial: "user"` (no positional collection) emits the partial's schema directly as `{type: object, properties: {...}}`; (c) `json.<key> @c, partial: "name" do |x| ... end` (block AND partial) → the block's body wins, the `partial:` is ignored (FR-004); (d) `json.<key> @c, partial: partial_name` (non-literal partial name) degrades to permissive `{}` and does NOT raise
- [X] T009 [Test] Extend `spec/unit/jbuilder_parser_spec.rb` for `case`/`when` merging: (a) `case x; when 1; json.a 1; when 2; json.b 2; else; json.c 3; end` produces a schema with properties `a`, `b`, `c`; (b) `case x; when 1; json.a 1; when 2; json.b 2; end` (no else) produces `a`, `b`; (c) multi-condition `when 1, 2; json.x 1; end` is treated as a single body; (d) a nested `case` inside an `if` branch is walked (the existing `if` walker recurses through statements that include `:case`)

### Implementation for the foundation

- [X] T010 Modify `JbuilderParser#add_property` in `lib/rails_openapi_generator/jbuilder_parser.rb`: in the `else` branch (after the existing `call[:block]` check, before falling through to `value_schema`), detect a literal `partial:` option in the call's argument hash via the existing `partial_name(call[:args])` helper (which already inspects bare_assoc_hash args). If `partial_name` returns a non-nil String, delegate to `partial_schema(call, seen)`. If the call has a positional non-hash argument BEFORE the hash (the collection form), emit `{type: array, items: <partial schema>}`. If not (the single-object form `json.user partial: "user"`), emit the partial's schema directly. Fall through to `value_schema` as today when no `partial:` option is present
- [X] T011 Add a helper method to detect "has positional non-hash arg" in `lib/rails_openapi_generator/jbuilder_parser.rb` — e.g. `positional_arg?(args)` returns true when `args` includes at least one element that is NOT a `:bare_assoc_hash`. Reuse for T010
- [X] T012 Extend `JbuilderParser#visit_statement` in `lib/rails_openapi_generator/jbuilder_parser.rb`: add `:case` to the list of conditional shapes (`%i[if unless elsif if_mod unless_mod case]`). Add a new helper `case_branch_bodies(case_node)` that walks the `:when` chain (and optional terminating `:else`) returning an Array of body-statement Arrays. Modify `conditional_bodies` to dispatch on `:case` → `case_branch_bodies(node)`, OR add the dispatch directly in `visit_statement` so the existing `conditional_bodies` stays focused on if/unless/elsif/else
- [X] T013 Implement `case_branch_bodies(node)` in `lib/rails_openapi_generator/jbuilder_parser.rb`: the AST shape is `[:case, <expr>, <chain>]` where `<chain>` starts at `node[2]` and is either a `:when` (with `[:when, conds, body, next_chain]`), an `:else` (`[:else, body]`), or `nil`. Walk the chain recursively, collecting `body` from each `:when` and the final `:else`. Return the list of bodies

**Checkpoint**: T008/T009 unit tests pass; full suite remains green (templates without these shapes still emit byte-identical schemas)

---

## Phase 3: User Story 1 - `json.<key>` partial recursion (Priority: P1) 🎯 MVP

**Goal**: The four sibling keys in the user's reported jbuilder (`today_logs`/`week_logs`/`month_logs`/`old_logs`) document with the resolved partial schema.

**Independent Test**: Generate against the dummy app. The `api/activity_logs#index` operation's response body schema should show `today_logs`, `week_logs`, `month_logs`, `old_logs` each as `{type: array, items: {type: object, properties: {id, message, created_at}}}`.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T014 [P] [US1] Add `spec/integration/jbuilder_partials_and_case_branches_spec.rb` asserting: the `/api/activity_logs` (GET index) operation's response body schema has four properties (`today_logs`, `week_logs`, `month_logs`, `old_logs`), each `{type: array, items: <object with id, message, created_at properties>}`; assert the partial recursion produced the exact same items schema for all four (no drift)

### Implementation for User Story 1

No new implementation — T010–T013 (foundation) delivers this story. T014 verifies it end-to-end.

**Checkpoint**: MVP — the user's reported pattern recovers full schema

---

## Phase 4: User Story 2 - `case` / `when` branch merging (Priority: P2)

**Goal**: A `case` block's `when` and `else` bodies all contribute their properties to the schema's union.

**Independent Test**: Generate against the dummy app. The `api/case_branches#show` operation's response body schema should show ALL properties from ALL branches.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T015 [P] [US2] Extend `spec/integration/jbuilder_partials_and_case_branches_spec.rb` for the case/when fixture: the `/api/case_branches/show` (GET) operation's response body schema includes EVERY property declared in EVERY `when` and `else` branch — verify the union semantics end-to-end

### Implementation for User Story 2

No new implementation — T012/T013 already deliver this story. T015 verifies it end-to-end.

**Checkpoint**: case/when branches merge into one schema

---

## Phase 5: Polish & Cross-Cutting Concerns

- [X] T016 [P] [Test] Extend `spec/integration/feature_001_regression_spec.rb` to confirm SC-004: existing jbuilder-backed endpoints (`api/users#index`, `api/users#show`) emit byte-identical schemas to `0.15.0` — the new walker code paths do NOT fire for templates that don't use the new shapes
- [X] T017 [P] [Test] Extend `spec/integration/determinism_spec.rb`: the four sibling keys' resolved partial schemas are byte-identical across two runs (no ordering drift); the case-merge union order is stable
- [X] T018 [P] Update `README.md`'s jbuilder section (if any; otherwise add a small paragraph in the response-detection section) explaining: (a) `json.<key> @c, partial: "name"` now resolves the partial recursively; (b) `case`/`when` branches union into one schema, same as `if`/`elsif`/`else`
- [X] T019 [P] Add a `0.16.0` entry to `CHANGELOG.md` describing both improvements + the SC-004 byte-identical guarantee for templates without these shapes
- [X] T020 Run `quickstart.md`-style end-to-end against the dummy app to confirm both improvements work in the full pipeline
- [X] T021 [P] Run RuboCop across the changed file and resolve any offenses

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: T002–T005 parallel; T006 sequential after T005; T007 sequential after T006
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS user stories. T008/T009 (tests) before T010–T013 (implementation); T010/T011 are tightly coupled (T011 is a helper called by T010); T012/T013 are tightly coupled (T013 is the helper called by T012)
- **User Stories (Phase 3–4)**: Depend on Foundational completion
- **Polish (Phase 5)**: Depends on user stories

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational — no new implementation, T014 verifies
- **US2 (P2)**: Depends only on Foundational — no new implementation, T015 verifies

### Within Each Phase

- Tests written first and failing before implementation (Constitution III)
- T011 before T010 (helper before its caller)
- T013 before T012 (helper before its caller)

### Parallel Opportunities

- Setup: T002–T005 parallel (all different files)
- Foundational tests: T008 and T009 parallel before T010–T013
- US1: T014 verification only (single task)
- US2: T015 verification only (single task)
- Polish: T016, T017, T018, T019, T021 parallel; T020 sequential at the end

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (version, partial fixture, index view, controller, routes)
2. Complete Phase 2: Foundational (parser tests + implementation)
3. Complete Phase 3: US1 verification — the four sibling keys document with the partial schema
4. **STOP and VALIDATE**: the user's reported pattern works end-to-end
5. Demo the MVP

### Incremental Delivery

1. Setup + Foundational → both shapes detected
2. US1 → partial resolution end-to-end (MVP)
3. US2 → case/when union end-to-end
4. Polish → regression, determinism, README, CHANGELOG

### Parallel Team Strategy

With multiple developers:

1. Developer A: Setup phase (T001–T007)
2. Once Setup is done: Developer A on US1 (T008, T010, T011, T014); Developer B on US2 (T009, T012, T013, T015)
3. Polish converges last

---

## Notes

- [P] = different files, no dependency on an incomplete task
- [US#] maps a task to its user story; [Test] marks a non-story test task
- All test specs MUST fail before their implementation task is started
- This feature is purely additive — templates that don't use the
  new AST shapes emit byte-identical schemas to `0.15.0` (SC-004,
  T016)
- The block-vs-partial precedence rule (FR-004) is naturally
  enforced because `add_property` already checks `call[:block]`
  first; the new `partial:` branch lives in the existing `else`
  branch
- The `:case` walker recursion is bounded by the AST size — no
  cycle risk, no depth bound needed (Ruby doesn't allow `case`
  expressions to recurse on themselves)
- Commit after each task or logical group
