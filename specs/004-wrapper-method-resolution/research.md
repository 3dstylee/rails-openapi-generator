# Phase 0 Research: Wrapper Method Resolution for File Downloads

## R1. Locating a called method's definition

**Decision**: Resolve a method name to its source by asking Ruby:
`controller_class.instance_method(name).source_location` returns `[file, line]`
for the method the controller would actually invoke. A method whose source file
is outside the host application (a gem / framework), or whose `source_location`
is nil (C-defined or metaprogrammed), is treated as **unresolvable**.

**Rationale**: `Module#instance_method` performs the real method-resolution
order — the controller's own methods, `include`d modules/concerns, and ancestor
controllers — so FR-002/FR-003 are satisfied without re-implementing the MRO.
`source_location` then points straight at the definition. Restricting to files
under the application root keeps resolution to app code (a controller calling
`params` or `render` resolves into a gem and is correctly skipped).

**Alternatives considered**:
- *Hand-walking `klass.ancestors` and parsing each module's file*: rejected —
  re-implements what `instance_method` already does, and gets `private`/override
  precedence wrong easily.
- *Executing the controller to introspect*: rejected — violates FR-009.

**Note**: `instance_method` finds `private` methods too (wrappers are usually
private), and raises `NameError` for an unknown name → caught, unresolvable.

## R2. Identifying receiverless calls in an action body

**Decision**: From a method's Ripper AST, collect the names of calls made with
**no explicit receiver** — node types `:command` (`foo bar`), `:vcall` (`foo`),
and `:fcall` inside `:method_add_arg` (`foo(bar)`). Calls with an explicit
receiver — `:call` / `:command_call` (`obj.foo`) — are **not** collected.

**Rationale**: Per the `/speckit-clarify` decision, only the controller's own
methods can reach the controller's `send_file`; an explicit-receiver call runs
on another object and cannot. Collecting only receiverless calls both bounds the
search and is semantically correct.

## R3. Bounded, cycle-guarded recursion

**Decision**: `WrapperDownloadResolver` walks the call graph depth-first:

1. If the current method body contains a `send_file`/`send_data` call → the
   action is a download (stop, true).
2. If the current depth equals the configured maximum → stop this branch.
3. For each receiverless call name, resolve it (R1); if resolved and not yet
   visited, recurse at depth + 1.
4. A method is identified for the visited-set by its resolved
   `"file:line"` source location; a method already visited in this resolution
   is skipped (cycle guard, FR-006).
5. If no branch reaches a download → false.

The maximum depth comes from configuration (R7), default 5.

**Rationale**: Depth-first with a visited set and a depth cap is the standard,
deterministic way to walk a possibly-cyclic graph. Identifying methods by source
location makes the cycle guard exact even when two classes share a method name.

## R4. Parsing resolved method bodies

**Decision**: Reuse `YardParser` to parse a resolved file into its `def` nodes
(it already returns every method in a file, keyed by name, with line numbers).
Select the def matching the resolved method name; if a file defines that name
more than once, disambiguate by the line nearest `source_location`. Parsed files
are cached per path so a shared concern is parsed once.

**Rationale**: `YardParser` already does exactly this Ripper parsing for
controllers; reusing it avoids a second parser (Constitution I).

## R5. The leaf check — `send_file` / `send_data`

**Decision**: A method body "is a download" when it contains a receiverless
call named `send_file` or `send_data`. The single receiverless-call scan from R2
yields both the leaf check and the recursion candidates — one pass.

**Rationale**: `RenderExtractor` already detects a *direct* `send_file` on the
action; `WrapperDownloadResolver` performs the same presence check on *wrapper*
bodies. The two scan for different shapes (`RenderExtractor` needs call
arguments; the resolver needs call names), so each keeps its own small scan
rather than sharing a forced abstraction.

## R6. Where resolution plugs into classification

**Decision**: `RenderClassifier` runs wrapper resolution **only** in the branch
where it would otherwise return `:undeterminable` — i.e. after a direct
`render json:`, `send_file`/`send_data`, `render html:`, and the view lookup
have all come up empty. If the resolver finds a download, the kind becomes
`:file_download`; otherwise `:undeterminable` as before.

**Rationale**: Honors the feature-003 precedence (JSON > direct download > HTML
> view) and FR-010 — only previously-undeterminable actions can change.

## R7. Configurable resolution depth

**Decision**: `Configuration` gains `download_resolution_depth`, an integer
defaulting to 5, validated as `>= 1`. The feature description and FR-005 specify
it as host-configurable.

**Rationale**: 5 covers realistic helper layering; exposing it satisfies FR-005
and lets an unusual codebase tune it. A single, validated config key is a
justified addition (Constitution I) because the requirement mandates it.

## R8. Obtaining the controller class

**Decision**: `SourceLocator` already constantizes the controller to find its
source file; it will additionally expose the resolved `Class`. The resolver
needs the live class for `instance_method`.

**Rationale**: The constant is already resolved there; returning it avoids a
second constantize and keeps that concern in one place.

## Resolved unknowns

All Technical Context items are resolved. No new runtime dependency. No
`NEEDS CLARIFICATION` markers remain — the call-following scope was settled in
`/speckit-clarify` (receiverless calls only).
