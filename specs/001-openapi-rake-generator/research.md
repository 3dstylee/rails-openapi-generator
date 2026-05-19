# Phase 0 Research: OpenAPI Rake Generator

## R1. Extracting `rails_param` validations without running the app

**Decision**: Extract `param!` declarations by **static source analysis** of
controller files, parsing the method body's AST.

**Rationale**: `rails_param` exposes its DSL through `param!` calls invoked
imperatively inside a controller action at request time — there is no static
metadata registry to read. The two ways to recover that information are
(a) executing the action and intercepting `param!`, or (b) parsing the action's
source. Option (a) violates FR-015 (no execution of host actions) and is
unreliable (params depend on request context, branching, auth). Option (b) is
deterministic (SC-008), side-effect free, and reuses the same AST already parsed
for YARD comments. The supported pattern is `param! :name, Type, options_hash`
with literal arguments; the type is a constant and options are a literal hash.

**Alternatives considered**:
- *Runtime interception*: rejected — executes host code, non-deterministic.
- *Requiring developers to declare params in a separate manifest*: rejected —
  defeats the feature's premise of reusing existing validations and adds
  duplicate work.

**Limitation captured as a requirement**: `param!` calls whose type or options
are non-literal (computed at runtime, behind a helper, or inside a conditional
that cannot be statically resolved) cannot be fully analyzed. Per FR-016 these
produce a warning and the parameter is emitted with whatever was resolved (at
minimum its name), the run continuing.

## R2. AST/source parser choice

**Decision**: Use **YARD** as the single source parser for each controller file.

**Rationale**: YARD must already be a dependency to read docstrings (the user's
explicit requirement). YARD builds a full code object graph and exposes each
method's docstring *and* its source/AST, so one parse per controller file yields
both the summary/description and the `param!` calls. Adding a second parser
(e.g. `parser`/`prism` directly) would be a redundant dependency, violating
Constitution I. YARD already wraps Ripper/Prism internally for the AST nodes
needed to read `param!` argument literals.

**Alternatives considered**:
- *`prism` directly*: rejected — a second parsing dependency for no gain over
  YARD's already-present AST access.
- *Regex scraping of source*: rejected — fragile, fails on multiline calls and
  comments, cannot reliably distinguish literals.

## R3. Discovering routes and mapping them to controller source

**Decision**: Read routes from `Rails.application.routes.routes`; map each route
to its controller class via `route.defaults[:controller]`/`[:action]`, then
resolve the class to a source file with `Module#const_source_location` (or
YARD's object graph).

**Rationale**: The in-memory route set is the authoritative, complete equivalent
of `rails routes` (FR-003) and is already loaded once the host app environment
is booted. `const_source_location` (Ruby 2.7+) gives the controller file without
executing it. Routes that resolve to no controller/action (redirects, mounted
engines) are detected here and handled per the spec's edge cases.

**Alternatives considered**:
- *Shelling out to `bin/rails routes` and parsing text*: rejected — lossy
  (no param/verb metadata for engines), slower, format not stable across Rails
  versions.

## R4. OpenAPI output version

**Decision**: Target **OpenAPI 3.1.0**.

**Rationale**: 3.1 aligns its schema model with JSON Schema 2020-12, which maps
cleanly onto `rails_param`'s type/constraint vocabulary (`in:`/enum,
`min:`/`max:`, `format:`). It is the current published version and is stated
explicitly in the document's `openapi` field (Constitution V, FR-005). Output is
validated in CI against the official 3.1 meta-schema via `json_schemer`.

**Alternatives considered**:
- *OpenAPI 3.0.3*: wider legacy tooling support but a divergent schema dialect
  and `nullable` quirks; rejected to keep the type mapping simple (Constitution
  I). Revisitable as a future config option only if a concrete need appears.

## R5. `rails_param` type & constraint → OpenAPI schema mapping

**Decision**: Fixed mapping table applied by `SchemaMapper`:

| `rails_param` input | OpenAPI 3.1 schema |
|---------------------|--------------------|
| `String` | `{ "type": "string" }` |
| `Integer` | `{ "type": "integer" }` |
| `Float`, `BigDecimal` | `{ "type": "number" }` |
| `TrueClass`/`Boolean` | `{ "type": "boolean" }` |
| `Array` | `{ "type": "array" }` |
| `Hash` | `{ "type": "object" }` |
| `Date`, `DateTime`, `Time` | `{ "type": "string", "format": "date"/"date-time" }` |
| `required: true` | parameter added to `required` / `required: true` |
| `in:` (range or list) | `enum` (list) or `minimum`/`maximum` (range) |
| `min:` / `max:` | `minimum` / `maximum` |
| `min_length:` / `max_length:` | `minLength` / `maxLength` |
| `format:` (regexp) | `pattern` |
| `blank: false` | `minLength: 1` (strings) |

**Rationale**: Covers `rails_param`'s documented option surface; unknown options
are ignored with a warning rather than failing (FR-016, FR-008 "where a
corresponding representation exists").

## R6. Routing parameters vs. dynamic path segments

**Decision**: Dynamic route segments (`:id`, etc.) become `in: path` parameters
(always required, `type: string` unless a `param!` of the same name refines it).
Remaining `param!` parameters become `in: query` for GET/DELETE and a JSON
`requestBody` object for POST/PUT/PATCH.

**Rationale**: Satisfies FR-009; matches conventional REST semantics so the
document is usable by standard OpenAPI tooling.

## R7. CLI booting the host Rails environment

**Decision**: The CLI requires `<rails-root>/config/environment.rb` (default
`Dir.pwd`, overridable via `--rails-root`), then calls the same
`Generator#generate` the rake task uses.

**Rationale**: Constitution IV requires a CLI with parity to the library/rake
interface. The rake task already runs inside a booted Rails env; the CLI just
boots it explicitly first. All real work stays in `Generator` — the CLI adds
only argument parsing and environment loading.

**Alternatives considered**:
- *No CLI, rake task only*: rejected — Constitution IV mandates a CLI.
- *CLI that re-implements generation*: rejected — Constitution IV requires the
  CLI be a thin wrapper.

## R8. Deterministic output

**Decision**: Sort paths alphabetically, operations by HTTP method in a fixed
order, parameters by name; serialize with stable key ordering.

**Rationale**: SC-008 requires identical output for unchanged input, making the
generated file diff-friendly and safe to commit.

## Resolved unknowns

All Technical Context items are resolved; no `NEEDS CLARIFICATION` markers
remain. The spec's open item ("exact OpenAPI minor version") is resolved by R4
(3.1.0).
