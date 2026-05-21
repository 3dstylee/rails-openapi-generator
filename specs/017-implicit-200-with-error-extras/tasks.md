---
description: "Task list for feature 017 — Implicit 200 with error extras"
---

# Tasks: Implicit 200 with error extras

**Input**: Design documents from `/specs/017-implicit-200-with-error-extras/`
**Prerequisites**: plan.md, spec.md

## Phase 1: Setup

- [X] T001 Bump `VERSION` to `0.17.0` in `lib/rails_openapi_generator/version.rb`
- [X] T002 [P] Add `spec/fixtures/dummy/app/controllers/api/silent_with_rescue_controller.rb` inheriting from `Api::ErrorRescuingController` with one action (`def silent_action; end`) — no render, no head, no redirect, no view
- [X] T003 Add a route `get "silent_with_rescue", to: "silent_with_rescue#silent_action"` in `spec/fixtures/dummy/config/routes.rb`
- [X] T004 Update the `spec/integration/generate_all_endpoints_spec.rb` route-list assertion to include `/api/silent_with_rescue`

## Phase 2: Tests (write first, must fail)

- [X] T005 Extend `spec/unit/response_builder_spec.rb` with a new describe block: an `:undeterminable` classification with no action-source render sites and only error-status extras MUST produce entries containing both the HTTP-method convention status (body-less) AND the extras' statuses
- [X] T006 Add `spec/integration/feature_017_implicit_200_spec.rb` asserting the fixture's `/api/silent_with_rescue` operation has responses `200` (body-less) plus the rescue_from statuses (`400`, `403`, `404`, `422`)

## Phase 3: Implementation

- [X] T007 Modify `ResponseBuilder#undeterminable_response` in `lib/rails_openapi_generator/response_builder.rb`: when `render_result.render_sites.empty?` AND the post-grouping entries lack an entry at the convention status, append a body-less `ResponseEntry` at `status_for(route, render_result)` and re-sort by ascending status

**Checkpoint**: T005/T006 pass; full suite remains green.

## Phase 4: Polish

- [X] T008 [P] Extend `spec/integration/feature_001_regression_spec.rb` to assert SC-002: jbuilder-backed and inline-render endpoints emit byte-identical responses to `0.16.0`
- [X] T009 [P] Extend `spec/integration/determinism_spec.rb` with a stability case for the new fixture (`/api/silent_with_rescue` responses identical across runs)
- [X] T010 [P] Add a paragraph to `README.md`'s response-bodies section noting the implicit 200 alongside `rescue_from` extras
- [X] T011 [P] Add `0.17.0` entry to `CHANGELOG.md`
- [X] T012 Run RuboCop and the full suite under two seeds; confirm zero offenses and zero failures
