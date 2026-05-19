<!--
SYNC IMPACT REPORT
Version change: (template, unversioned) → 1.0.0
Modified principles: none (initial ratification — all principles newly defined)
Added sections:
  - Core Principles (I–V): Simplicity & YAGNI; Specification Correctness;
    Test-First Discipline; Dual Interface Parity (Library + CLI);
    Versioned, Backward-Compatible Output
  - Technology & Dependency Constraints
  - Development Workflow & Quality Gates
  - Governance
Removed sections: none
Templates requiring updates:
  - .specify/templates/plan-template.md ✅ reviewed — generic "Constitution Check"
    gate compatible, no change needed
  - .specify/templates/spec-template.md ✅ reviewed — no constitution-driven
    mandatory section changes required
  - .specify/templates/tasks-template.md ✅ reviewed — task categories compatible;
    Test-First (Principle III) aligns with optional test-task guidance
Follow-up TODOs: none
-->

# rails-openapi-generator Constitution

## Core Principles

### I. Simplicity & YAGNI

The project MUST start simple and stay simple. Features, configuration options,
and abstractions MUST NOT be added until a concrete, demonstrated need exists.
Every new dependency, public method, CLI flag, or configuration key MUST be
justified by a current requirement — speculative extensibility is rejected.
When two designs satisfy a requirement, the one with fewer moving parts MUST be
chosen.

Rationale: An OpenAPI generator earns adoption by being predictable and easy to
reason about. Accumulated configuration surface and speculative abstraction make
the tool harder to learn, test, and maintain than the Rails apps it documents.

### II. Specification Correctness

Generated output MUST be valid OpenAPI: it MUST pass schema validation against
the targeted OpenAPI version before it is considered done. Generated documents
MUST accurately reflect the actual behavior of the Rails application — routes,
parameters, and response shapes that do not exist MUST NOT appear, and existing
ones MUST NOT be silently omitted. Any divergence between generated output and
real Rails behavior is a defect.

Rationale: A generator that emits inaccurate or invalid specs is worse than no
generator — it misleads API consumers and erodes trust permanently.

### III. Test-First Discipline

Every behavior change MUST be covered by an automated test. Tests MUST be written
before or alongside the implementation and MUST fail before the implementing
code exists. Generation logic MUST be verified with fixture Rails inputs and
asserted against expected OpenAPI output. No feature is complete until its tests
pass in CI.

Rationale: Generators transform structured input to structured output — a domain
where regressions are easy to introduce and invisible without fixture-based
tests covering real Rails constructs.

### IV. Dual Interface Parity (Library + CLI)

The project ships as a Ruby gem usable as a library AND as an executable CLI.
Any generation capability exposed through one interface MUST be reachable
through the other. The CLI MUST be a thin wrapper over the library API — it MUST
NOT contain generation logic of its own. CLI behavior follows a text protocol:
input via arguments/stdin, generated output to stdout, diagnostics and errors to
stderr, with a non-zero exit code on failure.

Rationale: Library users (Rake tasks, app integration) and CLI users (CI
pipelines, ad-hoc runs) must get identical results; duplicated logic across
interfaces guarantees they will drift.

### V. Versioned, Backward-Compatible Output

The gem MUST follow semantic versioning. Changes that alter generated OpenAPI
output for unchanged input, or that change the library/CLI public surface, MUST
be treated as breaking and released under a MAJOR version bump with documented
migration notes. The supported OpenAPI output version(s) MUST be stated
explicitly in documentation.

Rationale: Downstream consumers commit generated specs and build tooling on top
of them; unannounced output changes break their pipelines silently.

## Technology & Dependency Constraints

The project is implemented in Ruby and distributed as a gem with an accompanying
CLI executable. Runtime dependencies MUST be kept minimal — each one requires
explicit justification under Principle I and MUST be evaluated against the cost
it imposes on consuming Rails applications. The supported Ruby and Rails version
ranges MUST be declared in the gemspec and documentation, and MUST be exercised
in CI. The project MUST NOT depend on a specific Rails application's internal
code; it operates against public Rails introspection surfaces only.

## Development Workflow & Quality Gates

All changes land via pull request. A change MUST NOT be merged unless:

- Its tests exist, are meaningful, and pass in CI (Principle III).
- Generated-output changes are accompanied by updated fixtures and a stated
  rationale (Principle II).
- Any breaking change is identified, version-bumped, and documented with
  migration notes (Principle V).
- New configuration, flags, or dependencies carry an explicit justification
  (Principle I); reviewers MUST challenge unjustified additions.

Reviewers MUST verify constitution compliance as part of every review. Plans
produced by `/speckit-plan` MUST pass the Constitution Check gate before design
proceeds.

## Governance

This constitution supersedes other practices and conventions where they
conflict. Amendments MUST be proposed via pull request, MUST describe the
motivation and impact, and MUST update the version and dates below.

Versioning of this constitution follows semantic versioning:

- MAJOR: Backward-incompatible governance changes, or removal/redefinition of a
  principle.
- MINOR: A new principle or section is added, or existing guidance is materially
  expanded.
- PATCH: Clarifications, wording, and non-semantic refinements.

Compliance is reviewed on every pull request. Deviations from a principle MUST
be either corrected or explicitly recorded with justification in the affected
plan's Complexity Tracking before merge.

**Version**: 1.0.0 | **Ratified**: 2026-05-19 | **Last Amended**: 2026-05-19
