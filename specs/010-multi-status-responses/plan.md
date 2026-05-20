# Implementation Plan: Multi-Status Responses

**Branch**: `010-multi-status-responses` | **Date**: 2026-05-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/010-multi-status-responses/spec.md`

## Summary

Replace the per-operation single happy-path `Response` with a multi-entry
response set: every `render json:` and `head` call statically reachable
from the action — directly, through receiverless helpers (concern methods
included), and through `before_action` callbacks — contributes one entry
keyed by its HTTP status. Entries at the same status collapse: a known
body wins over no-body, and two distinct known bodies union into
`oneOf` (deterministically ordered). The "response shape could not be
determined" warning fires only when *no* render site contributes any
entry at all (the existing fallback path).

Technical approach: extend `RenderExtractor` to return *all* render sites
(not only the happy-path one); reuse `ControllerMethodWalker` to gather
helper method bodies; add a thin `BeforeActionResolver` that reads the
Rails callback chain (`controller_class._process_action_callbacks`) and
best-effort resolves `only:`/`except:` by re-parsing the controller's own
source file for literal-array filters. Refactor `Response` from a single
(status, body) holder to a list of `ResponseEntry(status, body)` values
(keeping the existing `kind` / `undeterminable` / `description` fields).
`DocumentBuilder.responses` iterates the entry list. No new dependency,
no new configuration. `rescue_from` and exception-implied statuses are
explicitly out of scope (FR-009).

## Technical Context

**Language/Version**: Ruby 3.1+ (unchanged).

**Primary Dependencies**: `railties`, `yard` — **no new dependency**.
Callback-chain introspection uses
`ActiveSupport::Callbacks#_process_action_callbacks`, an underscored but
long-stable Rails internal already relied on by many tools (e.g.
`abstract_controller-callbacks`).

**Storage**: N/A.

**Testing**: RSpec; the dummy Rails app fixture gains
`api/multi_status_controller.rb` with actions that exercise: happy +
error renders in one action; same-status collisions with identical and
with distinct shapes; a helper method whose render contributes a
status entry; a `before_action :authenticate` callback (declared in a
concern included in the controller) that contributes a 401 entry;
`before_action … only: [:update]` literal-array filtering; a
non-literal `if:` conditional (falls back to "applies to all actions").

**Target Platform**: Ruby 3.1+ / Rails 7.0+ host applications.

**Project Type**: Ruby gem — library API + rake task + CLI (unchanged).

**Performance Goals**: A small constant factor over today — the walker
already runs once per action; multi-status extraction reuses the same
walk. Callback-chain inspection runs once per controller class, then is
walked once per action. Documenting a controller with N actions and M
before_actions costs O(N·M) walks in the worst case (unchanged from
today's per-action helper walk).

**Constraints**: No execution of host actions or callbacks (FR-012);
deterministic output (FR-013); existing JSON / redirect / file_download /
html_page / `head`-only single-response shapes for an action without
extra renders MUST be byte-identical to today (SC-005); document still
passes OpenAPI 3.1 validation.

**Scale/Scope**: Substantial refactor — touches `Response` (struct
shape), `ResponseBuilder` (assembly), `RenderExtractor` (multi-site
extraction), `DocumentBuilder.responses` (iterates entry list), and
adds one new class (`BeforeActionResolver`). All consumers of
`response.status` / `response.body` (≈37 sites in `lib/` + `spec/`) are
updated.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Status |
|-----------|------------|--------|
| I. Simplicity & YAGNI | The feature genuinely needs a multi-entry model — single-Response is the wrong shape for what we want to emit. One new class (`BeforeActionResolver`) is added because nothing else owns the Rails callback chain. The `Response` refactor replaces — rather than adds alongside — the single-entry shape; net change is +1 small class and a struct reshape, not a layered abstraction. No new configuration. | PASS |
| II. Specification Correctness | Generated output gains accuracy: error-path renders are no longer dropped, so the documented OpenAPI describes more of what the API actually returns. Best-effort `only:` / `except:` resolution is precise when literal; the non-literal fallback over-documents rather than under-documents (truthful "may emit", per spec assumptions). OpenAPI 3.1 validation continues to pass. | PASS |
| III. Test-First Discipline | Fixture-driven; dummy app gains the `MultiStatusController` with one action per scenario. Unit and integration tests are written before each implementation task, asserting both presence (new entries) and absence (no regression on single-response operations). The `Response` reshape lands behind a sequence of failing unit tests on the new shape. | PASS |
| IV. Dual Interface Parity | No public interface change — rake task, CLI, and library API all gain multi-entry output through the shared `Generator`. | PASS |
| V. Versioned, Backward-Compatible Output | Output gains response entries that did not exist before for affected operations. Operations that only ever had one render keep byte-identical output (SC-005). Released as a MINOR bump (0.9.0) with a CHANGELOG entry. Determinism preserved (FR-013). | PASS (change is versioned) |

No violations — Complexity Tracking section omitted. The size of the
refactor is noted in Technical Context above, but it is in service of a
correctness fix rather than speculative extensibility (Principle I); the
change is justified by the user's reported case
(`PATCH /api/v2/workflow/custom_maisokus/:id`) and by FR-001's "every
render the action makes" requirement.

*Post-design re-check (after Phase 1): the design replaces a struct
field rather than layering on top of it, adds one focused class, and
preserves every existing precedence and resilience rule. Constitution
Check still PASSES.*

## Project Structure

### Documentation (this feature)

```text
specs/010-multi-status-responses/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── multi-status-output.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
lib/rails_openapi_generator/
├── render_extractor.rb         # MODIFIED — adds `render_sites` to RenderResult:
│                               #   every render's (status, schema, head_flag)
│                               #   in source order, alongside the existing
│                               #   happy-path fields.
├── before_action_resolver.rb   # NEW — reads
│                               #   controller_class._process_action_callbacks
│                               #   for the `:before` filters of
│                               #   `:process_action`, resolves each filter's
│                               #   method body via MethodResolver, and
│                               #   best-effort recovers `only:`/`except:` by
│                               #   parsing the controller's source file for
│                               #   literal-array filters. Returns a list of
│                               #   (method_node, only_set, except_set).
├── render_classifier.rb        # UNCHANGED in precedence (FR-010). The
│                               #   :json kind still wins over :redirect /
│                               #   :file_download / :html_page when any
│                               #   render contributes.
├── response.rb                 # MODIFIED — Response gains `entries: [Entry]`
│                               #   in place of `status` + `body`. `Entry =
│                               #   Struct.new(:status, :body)`. `kind`,
│                               #   `undeterminable`, `description`,
│                               #   `page_reference` unchanged.
├── response_builder.rb         # MODIFIED — builds a Response with a list of
│                               #   entries by grouping render_sites by
│                               #   status, applying the union rules in FR-004,
│                               #   and folding `head` calls per FR-005. Falls
│                               #   back to a single undeterminable entry when
│                               #   no render site contributes.
├── document_builder.rb         # MODIFIED — `responses` iterates
│                               #   `response.entries`. `response_content`
│                               #   continues to handle :html_page /
│                               #   :file_download / :redirect kinds at the
│                               #   entry level.
├── operation_builder.rb        # MODIFIED (small) — description-line code
│                               #   paths read from the primary entry's
│                               #   status / kind where needed.
└── generator.rb                # MODIFIED — wires BeforeActionResolver into
                                #   the response pipeline and stops short-
                                #   circuiting the "undeterminable" warning
                                #   when `response.entries` is non-empty.

spec/
├── unit/
│   ├── render_extractor_spec.rb             # MODIFIED — render_sites cases
│   ├── render_classifier_spec.rb            # MODIFIED — :json wins when any
│   │                                        #   render contributes
│   ├── response_builder_spec.rb             # MODIFIED — multi-entry assembly
│   │                                        #   + union/oneOf + head collapse
│   ├── document_builder_spec.rb             # MODIFIED — multi-entry emission
│   ├── before_action_resolver_spec.rb       # NEW — callback chain reading +
│   │                                        #   only/except recovery
│   └── (other unit specs)                   # MODIFIED where they reference
│                                            #   response.status / response.body
├── integration/
│   ├── multi_status_responses_spec.rb       # NEW — end-to-end assertions
│   ├── feature_001_regression_spec.rb       # MODIFIED — SC-005 unchanged-
│   │                                        #   output assertions
│   └── determinism_spec.rb                  # MODIFIED — multi-status entries
│                                            #   byte-identical across runs
└── fixtures/dummy/
    └── app/controllers/
        ├── api/multi_status_controller.rb   # NEW — actions exercising every
        │                                    #   scenario in the spec
        └── concerns/                        # NEW — concern with a
            └── auth_callback.rb             #   before_action callback for US3
```

**Structure Decision**: `Response` is reshaped from a single (status, body)
holder to a holder of an ordered list of `Entry(status, body)`. Single-status
operations get a list of one entry — byte-identical OpenAPI output.
Multi-status JSON operations get one entry per unique status, with the
union/oneOf rules applied at build time in `ResponseBuilder` (not in
`DocumentBuilder`, which stays a pure emitter). The new
`BeforeActionResolver` is the single place that touches the Rails callback
chain — it returns plain AST + filter metadata, so the rest of the pipeline
stays Rails-internals-free.

## Complexity Tracking

No constitution violations — section intentionally empty. The refactor is
broad in code-line terms but narrow in concept: one struct reshape, one
new resolver, and the same render-walk infrastructure used for two new
extraction passes (helpers + before_actions). The change is in service
of Principle II (Specification Correctness), not extensibility.
