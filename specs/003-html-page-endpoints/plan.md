# Implementation Plan: HTML Page & File Download Endpoints

**Branch**: `003-html-page-endpoints` | **Date**: 2026-05-19 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-html-page-endpoints/spec.md`

## Summary

Classify each controller action — by static inspection — as a JSON endpoint, an
HTML-page endpoint, a file-download endpoint, or undeterminable. Endpoints that
return a non-JSON response (HTML page or file download) are marked four ways: a
non-JSON response content type, a note in the operation description, a dedicated
tag ("HTML Pages" / "File Downloads"), and a machine-readable vendor extension.

Technical approach: a new `RenderClassifier` combines the AST signals already
read by `RenderExtractor` (extended to also detect `send_file`/`send_data` and
`render html:`/`render template:`) with `ViewLocator` (extended to resolve
`.html.*` views as well as `.json.jbuilder`). It yields a `Classification` that
`ResponseBuilder` turns into a kind-aware `Response`. No controller action is
executed (FR-011).

## Technical Context

**Language/Version**: Ruby 3.1+ (unchanged).

**Primary Dependencies**: `railties`, `yard` — **no new runtime dependency**.
Detection uses stdlib `Ripper` (already in use) and view-file existence checks.

**Storage**: N/A.

**Testing**: RSpec; the dummy Rails app fixture gains an HTML-rendering action
(with a `.html.erb` view), an action that renders a named HTML template, and a
`send_file` action.

**Target Platform**: Ruby 3.1+ / Rails 7.0+ host applications.

**Project Type**: Ruby gem — library API + rake task + CLI (unchanged).

**Performance Goals**: No regression — classification adds one view-file lookup
per action; generation for ~200 routes stays under 5 seconds.

**Constraints**: No execution of host actions or HTTP requests (FR-011);
deterministic output (FR-012); the document still passes OpenAPI 3.1 validation
(FR-012); JSON endpoints' output is unchanged (FR-013).

**Scale/Scope**: Hundreds of routes; the `spacely_web` reference app is heavily
HTML/SPA-mixed, so a large share of endpoints will classify as HTML pages.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Status |
|-----------|------------|--------|
| I. Simplicity & YAGNI | No new dependency. One new class (`RenderClassifier`) concentrates the JSON/HTML/download decision that is otherwise scattered; existing classes are extended, not duplicated. | PASS |
| II. Specification Correctness | Classification is read from real AST/view signals; output validated against the OpenAPI 3.1 meta-schema. Undeterminable actions are never guessed to be pages (FR-009/FR-010). | PASS |
| III. Test-First Discipline | New behavior is fixture-driven; the dummy app gains HTML and `send_file` actions; tests written before implementation. | PASS |
| IV. Dual Interface Parity | No interface change — rake task, CLI, and library API all gain the marks identically through the shared `Generator`. | PASS |
| V. Versioned, Backward-Compatible Output | Output changes for non-JSON endpoints (new content type, tag, note, extension). Additive — JSON endpoints unchanged — released as a MINOR bump (0.3.0) with a CHANGELOG entry. Output stays deterministic. | PASS (change is versioned) |

No violations — Complexity Tracking section omitted.

*Post-design re-check (after Phase 1): the design adds one class and one value
object, extends three, and introduces no dependency or new abstraction layer.
Constitution Check still PASSES.*

## Project Structure

### Documentation (this feature)

```text
specs/003-html-page-endpoints/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── classification-output.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
lib/rails_openapi_generator/
├── render_classifier.rb        # NEW — classify an action: JSON / HTML / download
├── render_extractor.rb         # MODIFIED — also detect send_file/send_data,
│                               #   render html:, render template:/:action
├── view_locator.rb             # MODIFIED — resolve .html.* views; return kind
├── response.rb                 # MODIFIED — Response gains kind + page_reference
├── response_builder.rb         # MODIFIED — build a kind-aware Response
├── operation_builder.rb        # MODIFIED — add the page/download note
├── document_builder.rb         # MODIFIED — content type, tags, vendor extension
├── report.rb                   # MODIFIED — count HTML pages / file downloads
└── generator.rb                # MODIFIED — wire RenderClassifier

spec/
├── unit/
│   ├── render_classifier_spec.rb       # NEW
│   ├── render_extractor_spec.rb        # MODIFIED — send_file/html/template cases
│   └── view_locator_spec.rb            # MODIFIED — html view resolution
├── integration/
│   └── html_page_endpoints_spec.rb     # NEW
└── fixtures/dummy/
    └── app/
        ├── controllers/api/pages_controller.rb   # NEW — html + send_file actions
        └── views/api/pages/show.html.erb         # NEW — an HTML view fixture
```

**Structure Decision**: Continue the one-class-per-pipeline-stage layout. The
classification decision gets its own class (`RenderClassifier`) so the
JSON/HTML/download branching lives in one tested place rather than spreading
through `Generator` and `ResponseBuilder`. `RenderExtractor` and `ViewLocator`
are extended to surface the new signals; `ResponseBuilder`, `OperationBuilder`,
and `DocumentBuilder` consume the resulting `kind`. JSON-endpoint behavior from
feature 002 is preserved unchanged.

## Complexity Tracking

No constitution violations — section intentionally empty.
