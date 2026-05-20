# Implementation Plan: Redirect Response Status Code

**Branch**: `009-redirect-status-code` | **Date**: 2026-05-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/009-redirect-status-code/spec.md`

## Summary

Document a `redirect_to` action with the correct redirect status (`302` by
default, or the action's explicit `status:` option) and no body — instead of
the current behavior, which falls through to "undeterminable", filed under the
HTTP-method convention status (e.g. `201` for `POST`) and emits a
"response shape could not be determined" warning.

Technical approach: `RenderExtractor` already discovers command calls in an
action's AST and already owns the Rails status-symbol → code table. Extend it
to also pick up `redirect_to` / `redirect_back` / `redirect_back_or_to` calls
and expose the redirect's 3xx status (default `302`, or the explicit `status:`
option) on `RenderResult`. `RenderClassifier` gains a `:redirect` kind that
sits just above the final `:undeterminable` fallback (below JSON / file
download / inline HTML / view-template). `ResponseBuilder` builds a body-less
redirect `Response` from that classification. `DocumentBuilder` emits a
redirect response with no `content` (a redirect has no body). No new class,
no new file, no new dependency, no new configuration.

## Technical Context

**Language/Version**: Ruby 3.1+ (unchanged).

**Primary Dependencies**: `railties`, `yard` — **no new dependency**. Detection
reuses the existing stdlib `Ripper` parse and `RenderExtractor::STATUS_CODES`.

**Storage**: N/A.

**Testing**: RSpec; the dummy Rails app fixture gains a controller whose
actions exercise redirects — a bare `redirect_to` on a `POST`, a
`redirect_to … status: :see_other`, a `redirect_to … status: 301`, a
`redirect_back_or_to` call, and a `redirect_to` alongside a happy-path
`render json:` (to assert precedence).

**Target Platform**: Ruby 3.1+ / Rails 7.0+ host applications.

**Project Type**: Ruby gem — library API + rake task + CLI (unchanged).

**Performance Goals**: No regression — redirect detection is part of the
existing single AST scan of each action.

**Constraints**: No execution of host actions (FR-001); deterministic output
(FR-011); only redirecting actions change documentation (FR-010); the document
still passes OpenAPI 3.1 validation.

**Scale/Scope**: Hundreds of routes; a contained change to three existing
classes (`RenderExtractor`, `RenderClassifier`, `ResponseBuilder`) and one
emission point (`DocumentBuilder.response_content`).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Status |
|-----------|------------|--------|
| I. Simplicity & YAGNI | No new class, file, dependency, or config. A `redirect_status` integer is added to `RenderResult`, a `:redirect` kind is added to `Classification`, and a single new branch is added to each of the classifier, the response builder, and the document builder's content map. No abstraction is introduced. | PASS |
| II. Specification Correctness | A `redirect_to` action is currently documented inaccurately on two counts (wrong status, spurious "undeterminable" body). The fix makes the documented status and body match the action's actual behavior. The `Location` header is not documented as a literal value because its target is dynamic — out of scope for v1 (assumption recorded). | PASS |
| III. Test-First Discipline | Fixture-driven; the dummy app gains redirect actions; unit and integration tests are written before implementation, asserting status, body absence, and the disappearance of the "response shape could not be determined" warning. | PASS |
| IV. Dual Interface Parity | No interface change — rake task, CLI, and library API all gain accurate redirect responses through the shared `Generator`. | PASS |
| V. Versioned, Backward-Compatible Output | Status codes change for actions that previously fell through to "undeterminable" because of a `redirect_to`. This is a correctness fix to output; released as a MINOR bump with a CHANGELOG entry. Output stays deterministic. | PASS (change is versioned) |

No violations — Complexity Tracking section omitted.

*Post-design re-check (after Phase 1): the design touches three existing
classes plus one branch in `DocumentBuilder.response_content`, adds no
abstraction, and removes one cause of the "undeterminable" warning. Constitution
Check still PASSES.*

## Project Structure

### Documentation (this feature)

```text
specs/009-redirect-status-code/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── redirect-output.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
lib/rails_openapi_generator/
├── render_extractor.rb     # MODIFIED — RenderResult gains `redirect_status`;
│                           #   detect redirect_to / redirect_back /
│                           #   redirect_back_or_to; resolve `status:` option
│                           #   (default 302); accept only 3xx.
├── render_classifier.rb    # MODIFIED — new `:redirect` kind, placed below
│                           #   JSON / file_download / inline html / view
│                           #   precedence and above the wrapper-download /
│                           #   undeterminable fallback.
├── response_builder.rb     # MODIFIED — build a body-less Response with the
│                           #   redirect status for `:redirect` classification.
└── document_builder.rb     # MODIFIED — `:redirect` kind emits no `content`
│                           #   (treated like html_page/file_download in the
│                           #   response_content switch).

spec/
├── unit/
│   ├── render_extractor_spec.rb     # MODIFIED — redirect_to detection cases
│   ├── render_classifier_spec.rb    # MODIFIED — :redirect classification
│   ├── response_builder_spec.rb     # MODIFIED — :redirect response shape
│   └── document_builder_spec.rb     # MODIFIED — redirect response has no body
├── integration/
│   └── redirect_response_spec.rb    # NEW — end-to-end fixture assertions
└── fixtures/dummy/
    └── app/controllers/api/
        └── redirects_controller.rb  # NEW — redirect actions for the fixture
```

**Structure Decision**: No new components. Detection lives on
`RenderExtractor` (which already evaluates `render status:` options and owns
the status-symbol → code map); classification gains a `:redirect` kind on the
existing `Classification` struct; response building gains a single branch on
`ResponseBuilder`; emission gains one branch in
`DocumentBuilder.response_content` (no `content` for `:redirect`, mirroring
how `html_page` and `file_download` are content-mapped). `OperationBuilder`'s
description note (`page_note`) is also extended with a one-line note for
redirects — symmetric with the existing HTML-page and file-download notes.
Everything else in the pipeline is untouched (FR-010).

## Complexity Tracking

No constitution violations — section intentionally empty.
