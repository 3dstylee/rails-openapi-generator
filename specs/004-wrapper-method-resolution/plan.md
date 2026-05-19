# Implementation Plan: Wrapper Method Resolution for File Downloads

**Branch**: `004-wrapper-method-resolution` | **Date**: 2026-05-19 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-wrapper-method-resolution/spec.md`

## Summary

Extend file-download detection so an action that streams a file through a helper
method — rather than calling `send_file`/`send_data` directly — is still
classified as a file download. When an action has no direct download signal, the
generator follows the action's receiverless method calls to their definitions,
inspects those bodies, and recurses through chains of wrappers until it finds a
`send_file`/`send_data` call or runs out of leads. Resolution is fully static,
bounded by a configurable depth (default 5), and cycle-guarded.

Technical approach: a `MethodResolver` locates a called method's definition by
asking Ruby itself — `controller_class.instance_method(name).source_location` —
which performs the full ancestor/module resolution, then parses that file. A
`WrapperDownloadResolver` drives the bounded, cycle-guarded recursion. The result
feeds `RenderClassifier`, which consults the resolver only when an action would
otherwise be undeterminable.

## Technical Context

**Language/Version**: Ruby 3.1+ (unchanged).

**Primary Dependencies**: `railties`, `yard` — **no new runtime dependency**.
Method location uses Ruby core reflection (`Module#instance_method`,
`Method#source_location`); bodies are parsed with the existing `YardParser`
(stdlib `Ripper`).

**Storage**: N/A.

**Testing**: RSpec; the dummy Rails app fixture gains controller actions that
download via a wrapper, via a chain of wrappers, via a wrapper in a concern, and
via a cyclic pair of wrappers.

**Target Platform**: Ruby 3.1+ / Rails 7.0+ host applications.

**Project Type**: Ruby gem — library API + rake task + CLI (unchanged).

**Performance Goals**: No regression — resolution is bounded by the depth cap
(default 5); each resolved file is parsed once and cached. Generation for ~200
routes stays under 5 seconds.

**Constraints**: No execution of host actions or helper methods (FR-009);
deterministic output (FR-011); only previously-undeterminable actions may change
(FR-010); document still passes OpenAPI 3.1 validation.

**Scale/Scope**: Hundreds of routes; wrapper chains are realistically 1–3 deep.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment | Status |
|-----------|------------|--------|
| I. Simplicity & YAGNI | No new dependency — method location reuses Ruby's own resolution (`instance_method`/`source_location`) instead of a hand-built ancestor walker. One config key (`download_resolution_depth`) is added because FR-005 requires it. Two focused new classes. | PASS |
| II. Specification Correctness | Resolution reflects real Ruby method dispatch; a download is reported only when a `send_file`/`send_data` call is actually reached. Unresolvable branches degrade to "not a download" — never guessed (FR-007). | PASS |
| III. Test-First Discipline | New behavior is fixture-driven; the dummy app gains wrapper / chained / concern / cyclic download actions; tests written before implementation. | PASS |
| IV. Dual Interface Parity | No interface change — rake task, CLI, and library API all gain wrapper resolution through the shared `Generator`. | PASS |
| V. Versioned, Backward-Compatible Output | Output changes only for actions that were previously undeterminable and now resolve to a download — additive. Released as a MINOR bump (0.4.0) with a CHANGELOG entry. Output stays deterministic. | PASS (change is versioned) |

No violations — Complexity Tracking section omitted.

*Post-design re-check (after Phase 1): the design adds two classes and one
configuration field, reuses Ruby reflection and the existing parser, and
introduces no dependency. Constitution Check still PASSES.*

## Project Structure

### Documentation (this feature)

```text
specs/004-wrapper-method-resolution/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── resolution-output.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
lib/rails_openapi_generator/
├── method_resolver.rb              # NEW — (controller class, method name) -> def AST node
├── wrapper_download_resolver.rb    # NEW — bounded, cycle-guarded recursive download search
├── configuration.rb               # MODIFIED — download_resolution_depth (default 5)
├── source_locator.rb               # MODIFIED — also expose the resolved controller class
├── render_classifier.rb            # MODIFIED — consult the resolver when undeterminable
└── generator.rb                    # MODIFIED — wire the resolver into classification

spec/
├── unit/
│   ├── method_resolver_spec.rb            # NEW
│   ├── wrapper_download_resolver_spec.rb   # NEW
│   └── configuration_spec.rb              # MODIFIED — depth setting
├── integration/
│   └── wrapper_download_spec.rb            # NEW
└── fixtures/dummy/
    └── app/controllers/
        ├── concerns/file_streaming.rb       # NEW — a download wrapper in a concern
        └── api/reports_controller.rb        # NEW — wrapper / chained / cyclic actions
```

**Structure Decision**: Two new classes with a single responsibility each.
`MethodResolver` answers "where is this method defined?" by delegating to Ruby's
own method resolution (`instance_method().source_location`) — this gives
correct ancestor/concern/parent handling for free, rather than re-implementing
the method-resolution order. `WrapperDownloadResolver` owns the recursion: depth
cap, visited-set cycle guard, and the leaf check for `send_file`/`send_data`.
`RenderClassifier` calls the resolver only in the branch where it would
otherwise return `:undeterminable`, so JSON / HTML / direct-download
classifications are untouched (FR-010).

## Complexity Tracking

No constitution violations — section intentionally empty.
