---
description: "Task list for Exclude Endpoints by Source Path"
---

# Tasks: Exclude Endpoints by Source Path

**Input**: Design documents from `/specs/007-exclude-source-paths/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Test tasks ARE included — Constitution Principle III (Test-First
Discipline) mandates every behavior change be covered by an automated test
written before/alongside implementation.

**Organization**: Tasks are grouped by user story (US1 P1, US2 P2). This
feature extends the existing gem (features 001–006).

## Path Conventions

Existing Ruby gem: runtime code in `lib/rails_openapi_generator/`, tests in
`spec/` with the dummy Rails app under `spec/fixtures/dummy/`.

---

## Phase 1: Setup

**Purpose**: Version bump

- [X] T001 Bump `VERSION` to `0.7.0` in `lib/rails_openapi_generator/version.rb` — the new `exclude_source_paths` setting is a versioned addition (Constitution V)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The `exclude_source_paths` setting and its matching query

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T002 [P] [Test] Extend `spec/unit/configuration_spec.rb` for `exclude_source_paths` (defaults to `[]`; `source_excluded?` matches a String entry by substring and a Regexp entry by pattern; returns false for a nil path; `validate!` rejects a non-Array value and a non-String/Regexp entry)
- [X] T003 Add `exclude_source_paths` (default `[]`), the `source_excluded?(path)` query, and `validate!` checks to `Configuration` in `lib/rails_openapi_generator/configuration.rb`

**Checkpoint**: `Configuration` exposes `exclude_source_paths` and `source_excluded?`; existing feature-001–006 specs still green

---

## Phase 3: User Story 1 - Exclude endpoints by a source-path substring (Priority: P1) 🎯 MVP

**Goal**: An endpoint whose controller source file path contains a configured substring is omitted from the document and reported as skipped.

**Independent Test**: Configure `exclude_source_paths` with a substring matching an existing dummy controller's source path, generate, and confirm that controller's endpoints are absent and listed as skipped.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T004 [P] [US1] Integration spec: a substring entry omits the matching controller's endpoints and records them as skipped; a non-matching controller is still documented; an empty list excludes nothing — in `spec/integration/exclude_source_paths_spec.rb`

### Implementation for User Story 1

- [X] T005 [US1] Add a guard in `Generator#build_endpoint` — after the controller source file is resolved, if `Configuration#source_excluded?` matches, record the route via `GenerationReport#skip` (with a source-path-exclusion reason) and drop it from the document — in `lib/rails_openapi_generator/generator.rb`

**Checkpoint**: MVP — `exclude_source_paths` substrings omit and report matching endpoints

---

## Phase 4: User Story 2 - Exclude endpoints by a regexp pattern (Priority: P2)

**Goal**: A regexp entry in `exclude_source_paths` excludes endpoints whose controller source file path matches it.

**Independent Test**: Configure `exclude_source_paths` with a regexp matching an existing dummy controller's source path, generate, and confirm that controller's endpoints are excluded.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T006 [P] [US2] Extend `spec/integration/exclude_source_paths_spec.rb` asserting a Regexp entry excludes matching endpoints, and a mixed String + Regexp list excludes an endpoint matching either

**Checkpoint**: Both String and Regexp entries exclude endpoints; US1 still passes

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Hardening and finalization

- [X] T007 [P] [Test] Extend `spec/integration/feature_001_regression_spec.rb` to assert that with `exclude_source_paths` unset the generated document is unchanged (FR-006/SC-004)
- [X] T008 [P] Update `README.md` with a note on the `exclude_source_paths` setting (alongside `route_filter`)
- [X] T009 [P] Add a `0.7.0` entry to `CHANGELOG.md` describing `exclude_source_paths`
- [X] T010 Run `quickstart.md` end-to-end against the dummy app and correct any discrepancies
- [X] T011 [P] Run RuboCop across the changed `lib/` files and resolve offenses

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **User Stories (Phase 3–4)**: All depend on Foundational completion
- **Polish (Phase 5)**: Depends on all targeted user stories

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational — the MVP
- **US2 (P2)**: Depends on Foundational; `Configuration#source_excluded?` (T003)
  already handles Regexp entries, so US2 adds no implementation — only its
  verification test

### Within Each User Story

- Tests written first and failing before implementation (Constitution III)
- `Configuration` (T003) before the `Generator` guard (T005)

### Parallel Opportunities

- Foundational: T002 (test) is independent of other work
- Polish: T007, T008, T009, T011 in parallel

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (`exclude_source_paths` + `source_excluded?`)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: a `"vendor/"`-style substring omits matching endpoints
5. Demo the MVP

### Incremental Delivery

1. Setup + Foundational → the setting and its query exist
2. US1 → substring exclusion (MVP — fixes the reported need)
3. US2 → regexp exclusion
4. Polish → regression, docs

---

## Notes

- [P] = different files, no dependency on an incomplete task
- [US#] maps a task to its user story; [Test] marks a non-story test task
- All test specs MUST fail before their implementation task is started
- This feature is opt-in — with `exclude_source_paths` unset the generated
  document is unchanged (FR-006, verified by T007)
- Commit after each task or logical group
