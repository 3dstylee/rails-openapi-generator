# Phase 1 Data Model: Exclude Endpoints by Source Path

This feature adds one configuration setting and one query method. No new
entities or value objects.

## Configuration (changed)

| New field | Type | Default | Notes |
|-----------|------|---------|-------|
| `exclude_source_paths` | Array of String / Regexp | `[]` | Patterns tested against a controller's resolved source file path. |

**New query method**:

| Method | Result |
|--------|--------|
| `source_excluded?(path)` | `true` when `path` is non-nil and matches any `exclude_source_paths` entry — a `String` entry by substring (`path.include?`), a `Regexp` entry by `match?`. `false` otherwise (including for a nil path). |

**Validation** (`Configuration#validate!`): `exclude_source_paths` must be an
Array; every entry must be a `String` or a `Regexp`. Any other value raises
`ConfigurationError` before generation begins.

## GenerationReport (unchanged shape)

No new field. A source-path-excluded route is recorded with the existing
`skip(route, reason)` and appears in the existing `skipped` list / `Skipped:`
summary section — the reason names the source-path exclusion.

## Generator flow (addition in **bold**)

```text
build_document → routes_to_process (route_filter applied in RouteCollector)
  for each resolvable route:
    build_endpoint(route):
      file = locate_source(route)
      **if Configuration#source_excluded?(file):**
      **  report.skip(route, "controller source excluded …"); return nil**
      … build the Endpoint as before …
  filter_map drops the nil → excluded route is absent from the document
```

Everything downstream (`OperationBuilder`, `DocumentBuilder`, response/parameter
handling) is unchanged — an excluded route simply never reaches it.
