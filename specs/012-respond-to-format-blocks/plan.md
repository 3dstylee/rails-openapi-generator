# Implementation Plan: respond_to Format Blocks

**Branch**: `012-respond-to-format-blocks` | **Date**: 2026-05-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/012-respond-to-format-blocks/spec.md`

## Summary

Detect `respond_to do |format| ... end` blocks in the action body,
helper methods, and `before_action` callbacks. For each
`format.<symbol>` call inside such a block, emit a "format gate"
render site that contributes a content type to the operation's
response: `:json` → `application/json` (schema from the action's
default `.json.jbuilder`, or from an explicit `render` in the block's
body), `:html` → `text/html` (schema from the action's default
`.html.*` view, or from an explicit `render` in the block's body).
At emission time, sibling sites at the same status with different
content types are merged into a single OpenAPI response entry that
carries multiple content types under one status key.

Technical approach: `RenderExtractor` gains `respond_to`-block
detection — find the block's parameter name, walk the block body for
`<param>.<format_symbol>` calls, and emit one site per gate. Each
gate site is either resolved by the block's inline render (reuses
feature 010 + 011 logic) or by a default-view lookup with a format
hint (reuses feature 011's `ViewLocator.format_hint:`). A new
`content_type` field on `RenderSite` carries the explicit
content-type marker (`application/json` / `text/html`) so emission
can merge same-status sites that differ only by content type.
`DocumentBuilder` learns to fold a single status's sites into one
entry with multiple content types. No new class, no new dependency,
no new configuration.

## Technical Context

**Language/Version**: Ruby 3.1+ (unchanged).

**Primary Dependencies**: `railties`, `yard` — **no new dependency**.
Detection reuses `Ripper`, `LiteralEvaluator`, `ViewLocator`, and
`JbuilderParser`.

**Storage**: N/A.

**Testing**: RSpec; the dummy Rails app fixture gains an action that
uses `respond_to do |format|; format.html { ... }; format.json; end`
and views in both formats. Additional fixture actions cover:
explicit `render json:` inside a `format.json` block; explicit
template render inside a `format.html` block; only-one-format
`respond_to` (only `format.json` or only `format.html`); a format
symbol the system does not map (e.g. `format.xml` — silently
ignored).

**Target Platform**: Ruby 3.1+ / Rails 7.0+ host applications.

**Project Type**: Ruby gem — library API + rake task + CLI (unchanged).

**Performance Goals**: One extra AST traversal pass per action that
contains a `respond_to` block. The pass is linear in the block's AST
size; the walker already enumerates the bodies once.

**Constraints**: No execution of host actions, callbacks, or
`respond_to` blocks (FR-012); deterministic output (FR-013);
operations that do not use `respond_to` MUST emit byte-identical
output to `0.10.0` (SC-004); document still passes OpenAPI 3.1
validation, including multi-content-type responses.

**Scale/Scope**: Narrow extension to two existing classes
(`RenderExtractor`, `DocumentBuilder`) plus one Generator
post-processing tweak. Touches ~3 files in `lib/`, ~2 unit specs, 1
integration spec, plus fixture additions.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Status |
|-----------|------------|--------|
| I. Simplicity & YAGNI | No new class. `RenderSite` gains one optional field (`content_type`) that is populated only for `respond_to`-gate sites. The format → content-type map is two entries (`:json`, `:html`); unknown symbols silently ignored — no speculative XML / CSV / PDF surface. `DocumentBuilder`'s emission path gains one merge step. The walker is reused; the view-locator is reused; no new resolver. | PASS |
| II. Specification Correctness | Today's output for a `respond_to` action is wrong: no entry at all (the block is invisible to the generator). The fix documents the actual content types the action emits. Multi-content-type emission under one status is the standard OpenAPI 3.1 shape; nothing fictional. | PASS |
| III. Test-First Discipline | Fixture-driven; the dummy app gains a controller with `respond_to` actions; unit and integration specs cover each user story and each edge case (default-view fallback, missing views, explicit renders inside blocks, unknown formats, single-format case). Tests fail before each implementation task. | PASS |
| IV. Dual Interface Parity | No public interface change — rake task, CLI, and library API all gain the same coverage through the shared `Generator`. | PASS |
| V. Versioned, Backward-Compatible Output | Operations that did NOT use `respond_to` in `0.10.0` emit byte-identical output (SC-004). Operations that did use `respond_to` go from "documented with no content" → "documented with one or two content types" — a correctness fix, released as a MINOR bump (0.11.0). Determinism preserved (content types sorted by name). | PASS (change is versioned) |

No violations — Complexity Tracking section omitted.

*Post-design re-check (after Phase 1): the design adds one optional
struct field, one detection pass on `RenderExtractor`, and one merge
step in `DocumentBuilder`. No new classes; no new configuration. The
existing classification precedence (`:json` > `:html_page` >
`:redirect` > `:undeterminable`) is preserved exactly. Constitution
Check still PASSES.*

## Project Structure

### Documentation (this feature)

```text
specs/012-respond-to-format-blocks/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── respond-to-output.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
lib/rails_openapi_generator/
├── render_extractor.rb         # MODIFIED — `RenderSite` gains
│                               #   `content_type`; `extract` and
│                               #   `collect_sites` also yield format-gate
│                               #   sites from any `respond_to` block in
│                               #   the body. Each gate either inherits
│                               #   the block's inline render (already
│                               #   handled by feature 010 + 011) or is
│                               #   emitted as an unresolved template site
│                               #   with the action's default view name
│                               #   and the format hint.
├── view_locator.rb             # UNCHANGED — `format_hint:` from feature
│                               #   011 is reused as-is.
├── response_builder.rb         # MODIFIED (small) — the per-status
│                               #   site-grouping in `entries_from_sites`
│                               #   already collapses by status. The
│                               #   group's body computation needs to be
│                               #   aware of `content_type` so the JSON
│                               #   site's body and the HTML site's body
│                               #   don't union (they're separate content
│                               #   types). The ResponseEntry gains a
│                               #   `content_types` field carrying the
│                               #   per-content-type body map.
├── response.rb                 # MODIFIED — `ResponseEntry` gains an
│                               #   optional `content_types: Hash<String,
│                               #   Hash | nil>` field. When set, it
│                               #   carries the per-content-type body for
│                               #   the entry; the single-content-type
│                               #   `body` field stays as today for
│                               #   backwards compatibility.
└── document_builder.rb         # MODIFIED — `entry_content` emits a
                                #   multi-content-type map when the entry's
                                #   `content_types` is set; falls back to
                                #   today's per-kind emission otherwise.

spec/
├── unit/
│   ├── render_extractor_spec.rb            # MODIFIED — respond_to
│   │                                       #   detection cases
│   ├── response_builder_spec.rb            # MODIFIED — multi-content-type
│   │                                       #   entry assembly
│   └── document_builder_spec.rb            # MODIFIED — multi-content-type
│                                           #   emission cases
├── integration/
│   └── respond_to_format_blocks_spec.rb    # NEW — end-to-end coverage
│                                           #   for US1/US2 + edge cases
└── fixtures/dummy/
    ├── app/controllers/api/
    │   └── respond_to_controller.rb        # NEW — actions exercising
    │                                       #   respond_to blocks
    └── app/views/api/respond_to/
        ├── index.json.jbuilder             # NEW
        ├── index.html.erb                  # NEW
        ├── json_only.json.jbuilder         # NEW (only-JSON case)
        └── html_only.html.erb              # NEW (only-HTML case)
```

**Structure Decision**: No new components. The detection lives where
all the other render detection lives — `RenderExtractor`. The
content-type concept is added narrowly: a new optional field on
`RenderSite` (when set, marks the site as a format-gate contribution
keyed by a specific content type) and a new optional field on
`ResponseEntry` (when set, carries per-content-type bodies; otherwise
the entry's single `body` is emitted as today). `DocumentBuilder`
fans the multi-content-type map into the OpenAPI `content` map. The
existing per-status grouping in `ResponseBuilder` is unchanged in
shape — only the body-computation step learns to split by
`content_type`.

## Complexity Tracking

No constitution violations — section intentionally empty. The
feature is narrow: one detection pass, one optional field on two
structs, and one fan-out step in `DocumentBuilder`. All other
behaviors — including precedence, kind classification, and warning
channels — are inherited unchanged from features 010 and 011.
