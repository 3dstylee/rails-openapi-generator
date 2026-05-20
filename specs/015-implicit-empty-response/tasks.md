---
description: "Task list for Implicit Empty Response"
---

# Tasks: Implicit Empty Response

**Input**: Design documents from `/specs/015-implicit-empty-response/`

**Prerequisites**: plan.md, spec.md, research.md

**Tests**: Test task is included — the test surface IS the
behavioral assertion (the existing `response_resilience_spec.rb`
assertion is inverted from "warning fires" to "warning does not
fire"). Constitution Principle III is satisfied by the test
ordering described below.

**Organization**: Single user story (US1 from the spec); the
P2 story is a backward-compat guarantee verified by the existing
suite remaining byte-identical. The whole feature is ≤ 10 lines
of production code plus one assertion flip — the task structure
is deliberately minimal.

## Path Conventions

Existing Ruby gem: runtime code in `lib/rails_openapi_generator/`,
tests in `spec/`.

---

## Phase 1: Setup

**Purpose**: Version bump

- [X] T001 Bump `VERSION` to `0.15.0` in `lib/rails_openapi_generator/version.rb` — warning-channel behavior changes (Constitution V; the OpenAPI document output is unchanged but the `GenerationReport.warnings` channel and the `Response#undeterminable?` predicate change)

---

## Phase 2: Behavioral Change

**Purpose**: Make the `:undeterminable` no-sites branch emit a non-undeterminable Response; invert the existing test assertion to match.

### Test first (write to fail) ⚠️

- [X] T002 [Test] Invert the existing assertion in `spec/integration/response_resilience_spec.rb`: change `expect(report.warnings.join("\n")).to match(%r{/api/posts: response shape could not be determined})` to `expect(report.warnings.join("\n")).not_to match(%r{/api/posts: response shape could not be determined})`. ALSO add (or strengthen) an assertion that the operation's `responses` map has exactly `["200"]` with no `content` key — guards byte-identity of the OpenAPI output

### Implementation

- [X] T003 Change `ResponseBuilder#undeterminable_response` in `lib/rails_openapi_generator/response_builder.rb`: in the `if sites.empty?` branch, replace `empty = empty_body_path?(render_result); return Response.new(status: status_for(route, render_result), undeterminable: !empty)` with `return Response.new(status: status_for(route, render_result))`. The `undeterminable:` keyword defaults to `false` on the `Response` struct, so we can drop it entirely — the OpenAPI output stays the same, the warning naturally stops firing because `response.undeterminable?` is now false, and the local `empty` variable is no longer needed

---

## Phase 3: User Story 1 - No-signal actions stop noising the warning channel (Priority: P1) 🎯 MVP

**Goal**: Actions with no static response signal no longer fire the `"response shape could not be determined"` warning.

**Independent Test**: After T002 + T003, `spec/integration/response_resilience_spec.rb` passes — the warning does not fire for `api/posts#index`, and the OpenAPI operation shape is unchanged.

No additional tasks for US1 — the behavioral change (T003) and the test flip (T002) together deliver the story.

---

## Phase 4: Polish & Cross-Cutting Concerns

- [X] T004 [P] [Test] Run the full test suite and confirm 470+ examples, 0 failures across multiple seeds (seed stability check — the change should be deterministic and order-independent)
- [X] T005 [P] Update `README.md` with a short note: the "response shape could not be determined" warning has been narrowed; it no longer fires for actions whose code produces no static signal (Rails returns a body-less success at runtime in this case)
- [X] T006 [P] Add a `0.15.0` entry to `CHANGELOG.md` describing the warning suppression for no-signal actions, the unchanged OpenAPI document output, the trade-off (serializer-based responses no longer fire the warning either; users who rely on the warning to spot Blueprinter/AMS gaps should track those endpoints separately)
- [X] T007 [P] Run RuboCop across the changed file (`lib/rails_openapi_generator/response_builder.rb`) and resolve any offenses (likely none — the change makes the code shorter)

---

## Dependencies & Execution Order

- **T001** before T002/T003 (version bump signals the release)
- **T002** before **T003** (test-first: assertion flipped, observe failure, then production-code fix lands)
- **T003** is the entire behavioral change
- **T004–T007** can run in parallel after T003 (different files)

---

## Implementation Strategy

This is the smallest feature in the project's history.

1. Bump VERSION (T001)
2. Flip the assertion in `response_resilience_spec.rb` (T002) — run the spec, confirm it fails (warning still fires)
3. Apply the one-line behavioral change in `response_builder.rb` (T003) — run the spec, confirm it passes
4. Run the full suite — confirm 0 failures across multiple seeds (T004)
5. Update README + CHANGELOG (T005, T006)
6. RuboCop (T007)

Estimated effort: ≤ 30 minutes including verification.

---

## Notes

- The behavioral change is a single line in
  `ResponseBuilder#undeterminable_response`'s `sites.empty?` branch.
- No new fixture is needed — the existing `api/posts#index`
  fixture is the perfect no-signal case.
- The OpenAPI document output for the affected operation is
  byte-identical to `0.14.0`; only the warning channel and the
  internal `Response#undeterminable?` predicate change.
- Serializer-based responses (Blueprinter / AMS / etc.) that
  fall through this path will also stop firing the warning. This
  is recorded in the CHANGELOG (T006) as a deliberate trade-off.
