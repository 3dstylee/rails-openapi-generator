# Phase 0 Research: Exclude Endpoints by Source Path

## R1. Match semantics

**Decision**: Each `exclude_source_paths` entry is matched against the
**absolute path** of the resolved controller source file. A `String` entry
matches when it is a substring of that path (`path.include?(entry)`); a `Regexp`
entry matches when `entry.match?(path)`. A route is excluded when any entry
matches.

**Rationale**: A substring against the absolute path makes `"vendor/"` work
regardless of where the app root is, and is the least surprising for the stated
use case. Regexp entries cover precise matches. This mirrors the dual
string/regexp shape common to Ruby ignore-style configuration.

## R2. Where the check runs

**Decision**: `Generator#build_endpoint` already calls `locate_source(route)` to
resolve the controller source file. Immediately after, it consults
`Configuration#source_excluded?(file)`; when true it records the route as
skipped and returns nil, so `build_document`'s `filter_map` drops it.

**Rationale**: The source file is resolved exactly once, in `build_endpoint`;
checking there avoids a second resolution. Returning nil reuses the existing
`filter_map` drop path.

**Alternatives considered**:
- *Filtering in `routes_to_process`*: rejected — that stage has not resolved the
  source file, so it would need a second `SourceLocator` call.

## R3. Reporting

**Decision**: An excluded route is recorded via the existing
`GenerationReport#skip(route, reason)`, with a reason naming the source-path
exclusion. It appears in the run report's existing `Skipped:` section.

**Rationale**: One consistent reporting path for all skipped routes (FR-004);
no new report field.

## R4. Configuration and validation

**Decision**: `Configuration` gains `exclude_source_paths`, defaulting to `[]`.
`Configuration#validate!` rejects a value that is not an Array, or an Array
containing an entry that is neither a `String` nor a `Regexp`, raising
`ConfigurationError` before generation. A `source_excluded?(path)` query method
encapsulates the matching (R1) and returns false for a nil path.

**Rationale**: Fails fast on misconfiguration (FR-008). Keeping the matching on
`Configuration` makes it unit-testable and keeps `Generator` to a one-line
guard.

## R5. Interaction with `route_filter`

**Decision**: `exclude_source_paths` and `route_filter` are independent and both
apply. `route_filter` runs in `RouteCollector` (route-level); source-path
exclusion runs in `build_endpoint` (source-level). A route is excluded if either
drops it.

**Rationale**: Satisfies FR-007; the two filter on different things (the route
vs. where the controller lives) and compose naturally.

## R6. Default behavior

**Decision**: With `exclude_source_paths` empty (the default), `source_excluded?`
returns false for every path, so no route is excluded and the generated document
is byte-identical to the pre-feature output.

**Rationale**: Satisfies FR-006/SC-004 — the feature is purely opt-in.

## Resolved unknowns

All Technical Context items are resolved. No new dependency, class, or file. No
`NEEDS CLARIFICATION` markers — the feature description and the recorded
assumption (exclusion applies only to resolved sources) fully specify behavior.
