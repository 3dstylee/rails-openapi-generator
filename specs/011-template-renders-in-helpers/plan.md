# Implementation Plan: Template Renders in Helpers

**Branch**: `011-template-renders-in-helpers` | **Date**: 2026-05-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/011-template-renders-in-helpers/spec.md`

## Summary

Extend the feature-010 render-site collector so that template renders —
`render "path"`, `render :symbol`, `render template:`, `render action:` —
contribute response sites the same way `render json:` and `head` calls
do today. The site is generated in the action body **and** in every
helper / `before_action` body the existing walker reaches. Each
template-render site carries a format hint from its `formats:` option
(when literal); the Generator resolves each site to a view file via the
existing `ViewLocator`, parses the jbuilder when the view is a
`.json.jbuilder`, and emits the result as a JSON site (with schema or
body-less) or as an HTML-page site. JSON precedence at the same status
is preserved per feature 010 FR-005.

Technical approach: `RenderExtractor` gains template-render detection
in `collect_sites` / `extract` (already aware of helper bodies thanks
to feature 010), producing a new `RenderSite` variant carrying
`template_name` and `format_hint`. The Generator post-processes those
sites by calling `ViewLocator` and `JbuilderParser` to produce final
sites (JSON-with-schema, HTML-page, or status-known body-less),
indistinguishable from the JSON sites already in the pipeline. No new
class, no new dependency, no new configuration. `respond_to` /
`format.json { … }` and dynamic dispatch remain out of scope (FR-009).

## Technical Context

**Language/Version**: Ruby 3.1+ (unchanged).

**Primary Dependencies**: `railties`, `yard` — **no new dependency**.
Detection reuses `Ripper`, `LiteralEvaluator`, `ViewLocator`, and
`JbuilderParser`.

**Storage**: N/A.

**Testing**: RSpec; the dummy Rails app fixture gains a controller and
a view that exercise: a helper-method template render that resolves
to a `.json.jbuilder` (the motivating case); a helper-method template
render with `formats: :html` that resolves to an `.html.erb`; a
template render whose requested format does not exist (body-less
fallback); a template render in a `before_action` callback. Existing
HTML-page and jbuilder-view fixtures must continue to emit
byte-identical output (SC-004).

**Target Platform**: Ruby 3.1+ / Rails 7.0+ host applications.

**Project Type**: Ruby gem — library API + rake task + CLI (unchanged).

**Performance Goals**: A small constant factor over today — one extra
view-locate-and-parse per template-render site. The number of template
sites is bounded by the number of `render` calls in the reachable
bodies, which the walker already enumerates.

**Constraints**: No execution of host actions or callbacks (FR-010);
deterministic output (FR-011); operations whose existing output
(jbuilder-view single render, HTML-page single render, single
`render json:`) was correct today MUST be byte-identical (SC-004);
document still passes OpenAPI 3.1 validation.

**Scale/Scope**: Narrow extension to two existing classes
(`RenderExtractor`, `Generator#collect_extra_sites`) plus a small
helper to format-hint-resolve a template-render site. No new top-level
class. Touches ~6 files in `lib/`, ~3 unit specs, 1 integration spec,
plus fixture additions.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Status |
|-----------|------------|--------|
| I. Simplicity & YAGNI | No new class, file, dependency, or config. `RenderSite` gains `template_name` and `format_hint`; the existing `ViewLocator` and `JbuilderParser` are the only resolution pipeline. The "prefer JSON" lookup is the existing behavior — the format hint refines it; no parallel resolver is introduced. | PASS |
| II. Specification Correctness | The motivating bug shows missing documentation today (helper template render → no happy entry). The fix documents the actual response shape. The format hint disambiguates the JSON-vs-HTML choice precisely when the developer is explicit, otherwise inherits today's `ViewLocator` "prefer JSON" behavior. Body-less entries for missing views are *more* accurate than today's silent drop. | PASS |
| III. Test-First Discipline | Fixture-driven; the dummy app gains a controller whose update happy path is in a helper, plus a jbuilder view and an HTML view for the same controller. Unit and integration specs cover each user story and each edge case (format-hint resolution, view-missing fallback, JSON-wins-at-same-status, `before_action` carrier). Tests fail before each implementation task. | PASS |
| IV. Dual Interface Parity | No public interface change — rake task, CLI, and library API all gain the same coverage through the shared `Generator`. | PASS |
| V. Versioned, Backward-Compatible Output | Operations whose only render today is a single action-body template render (e.g. an HTML page or a jbuilder-view JSON action) emit byte-identical output (SC-004). Operations whose helper template renders were silently dropped today gain new entries — a correctness fix, released as a MINOR bump (0.10.0). Determinism preserved. | PASS (change is versioned) |

No violations — Complexity Tracking section omitted.

*Post-design re-check (after Phase 1): the design extends one struct,
adds one helper method on the Generator (`resolve_template_site`), and
adds two new detection sites in `RenderExtractor`. The existing
view-resolution path is reused unchanged for the no-`formats:` case.
Constitution Check still PASSES.*

## Project Structure

### Documentation (this feature)

```text
specs/011-template-renders-in-helpers/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── template-render-output.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
lib/rails_openapi_generator/
├── render_extractor.rb         # MODIFIED — `RenderSite` gains
│                               #   `template_name` and `format_hint`;
│                               #   `extract` and `collect_sites` also
│                               #   yield a site for every `render "name"`
│                               #   / `render :symbol` / `render template:`
│                               #   / `render action:` call, with its
│                               #   `formats:` option resolved when literal.
├── view_locator.rb             # MODIFIED — `locate_view` accepts an
│                               #   optional `format_hint:` (Symbol or
│                               #   Array<Symbol>) and returns the matching
│                               #   view; falls back to today's
│                               #   "prefer JSON" lookup when nil.
├── response_builder.rb         # UNCHANGED in structure — the new sites
│                               #   look indistinguishable from today's
│                               #   sites once the Generator resolves
│                               #   them, so the union/dedup pipeline is
│                               #   reused as-is.
├── render_classifier.rb        # UNCHANGED — precedence rules already
│                               #   pick `:json` over `:html_page` when
│                               #   any render contributes a JSON site
│                               #   (feature 010 FR-007).
└── generator.rb                # MODIFIED — `collect_extra_sites` now
                                #   post-processes template-render sites:
                                #   resolves each via `ViewLocator` (with
                                #   the site's format hint) and converts
                                #   it into a JSON site (schema from
                                #   `JbuilderParser`), an HTML-page site
                                #   (body nil, kind :html_page), or a
                                #   status-known body-less JSON site.

spec/
├── unit/
│   ├── render_extractor_spec.rb            # MODIFIED — template-render
│   │                                       #   site cases (formats hint,
│   │                                       #   action-vs-helper sources)
│   ├── view_locator_spec.rb                # MODIFIED — format-hint
│   │                                       #   resolution cases
│   └── (other unit specs)                  # UNCHANGED unless they
│                                           #   referenced details of
│                                           #   template-name resolution
├── integration/
│   └── template_renders_in_helpers_spec.rb # NEW — end-to-end coverage
│                                           #   for US1/US2/US3, fixture-
│                                           #   based
└── fixtures/dummy/
    ├── app/controllers/api/
    │   └── template_renders_controller.rb  # NEW — actions exercising
    │                                       #   helper-template renders
    └── app/views/api/template_renders/
        ├── show.json.jbuilder              # NEW — jbuilder for US1
        ├── show.html.erb                   # NEW — html alt for US2
        └── forbidden.json.jbuilder         # NEW — for the
                                            #   before_action callback
                                            #   case (US3)
```

**Structure Decision**: No new components. `RenderSite` already carries
`status`, `schema`, `head`, `source` (feature 010); two optional fields
(`template_name`, `format_hint`) are added — they are populated only
for template-render sites, and the existing JSON / head sites leave
them nil. The Generator's `collect_extra_sites` (already responsible
for combining action / helper / before_action sites) gains a
post-processing step that resolves any template-render site to a final
JSON-with-schema, HTML-page, or body-less site. By the time sites
reach `ResponseBuilder`, every site is in the same "ready to group by
status and union" shape — no new branch is added to the response
builder. The format hint is honored in `ViewLocator` so the resolution
order remains in one place.

## Complexity Tracking

No constitution violations — section intentionally empty. The feature
is intentionally narrow: it generalizes one detection rule (template
renders) across one already-known walking surface (helpers +
before_action), routed through one already-known resolver
(`ViewLocator` + `JbuilderParser`).
