# Phase 1 Data Model: OpenAPI Rake Generator

These are the in-memory domain objects the generator builds while transforming
the Rails route set into an OpenAPI document. None are persisted; the only
output artifact is the OpenAPI document file.

## Configuration

User-supplied settings for a generation run.

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `output_path` | String | `doc/openapi.json` | Destination file (FR-012). |
| `format` | Symbol | inferred from `output_path` extension (`:json`/`:yaml`) | Serialization format. |
| `route_filter` | callable / pattern | include all | Selects which routes are processed (FR-013). |
| `title` | String | host app class name | Document `info.title`. |
| `api_version` | String | `"1.0.0"` | Document `info.version`. |

**Validation**: `output_path` parent directory must be writable; `format` must
be `:json` or `:yaml`.

## Route

A discovered mapping from the Rails route set; input to the pipeline.

| Field | Type | Notes |
|-------|------|-------|
| `http_method` | String | `GET`, `POST`, … (one Route per method). |
| `path` | String | Rails path pattern, e.g. `/users/:id`. |
| `controller` | String / nil | Controller key from route defaults. |
| `action` | String / nil | Action name from route defaults. |
| `path_params` | [String] | Dynamic segment names parsed from `path`. |
| `external` | Boolean | True for redirects / mounted engines (no action). |

**Rules**: A Route with no resolvable `controller`+`action` and `external=false`
is skipped with a warning (edge case "route without a backing action"). An
`external` Route still yields an Endpoint with path/method only.

## ControllerSource

The parsed source of one controller file, cached so each file is parsed once.

| Field | Type | Notes |
|-------|------|-------|
| `controller` | String | Controller key. |
| `file_path` | String | Resolved via `const_source_location`. |
| `actions` | { action => ActionSource } | Per-action parsed data. |

## ActionSource

Static-analysis result for a single controller action method.

| Field | Type | Notes |
|-------|------|-------|
| `action` | String | Method name. |
| `doc_comment` | DocComment / nil | Parsed YARD docstring above the method. |
| `param_calls` | [ParamCall] | `param!` calls found in the method body. |

## DocComment

Human-readable text extracted from a YARD docstring (FR-010).

| Field | Type | Notes |
|-------|------|-------|
| `summary` | String / nil | First line of the docstring. |
| `description` | String / nil | Remaining body of the docstring. |

**Rules**: An unparseable comment yields `nil` fields and a warning; the
Endpoint is still produced (FR-011, edge case "malformed documentation
comment").

## ParamCall

One statically resolved `rails_param` `param!` declaration.

| Field | Type | Notes |
|-------|------|-------|
| `name` | String | Parameter name. |
| `type` | String / nil | Declared type constant; `nil` if non-literal. |
| `required` | Boolean | From `required:` option. |
| `constraints` | Hash | `in:`, `min:`, `max:`, `format:`, etc. (literal only). |
| `fully_resolved` | Boolean | False when type/options were non-literal (R1). |

## Parameter

A normalized parameter ready for the OpenAPI document (Key Entity "Parameter").

| Field | Type | Notes |
|-------|------|-------|
| `name` | String | |
| `location` | Symbol | `:path`, `:query`, or `:body` (R6). |
| `required` | Boolean | Path params are always required. |
| `schema` | Hash | OpenAPI schema from `SchemaMapper` (R5). |

**Derivation**: `path_params` ∪ `param_calls`. When a name appears in both, the
path-segment location wins and the `param!` schema refines the type (edge case
"conflicting information" — validation-derived definition takes precedence).

## Endpoint

The fully assembled description of one operation (Key Entity "Endpoint").

| Field | Type | Notes |
|-------|------|-------|
| `http_method` | String | |
| `path` | String | |
| `summary` | String / nil | From DocComment. |
| `description` | String / nil | From DocComment. |
| `parameters` | [Parameter] | Path + query parameters. |
| `request_body` | Hash / nil | Body schema for write methods (R6). |
| `operation_id` | String | Deterministic, e.g. `controller#action` or method+path. |

**Rules**: Always produced once a Route resolves, even with empty parameters and
no comment (FR-011).

## OpenApiDocument

The complete generated artifact (Key Entity "OpenAPI Document").

| Field | Type | Notes |
|-------|------|-------|
| `openapi` | String | `"3.1.0"` (R4). |
| `info` | Hash | `title`, `version` from Configuration. |
| `paths` | Hash | One entry per path, operations keyed by lowercased method. |

**Rules**: MUST validate against the OpenAPI 3.1 meta-schema (FR-005). Paths,
operations, and parameters are emitted in a stable sorted order (R8, SC-008).

## GenerationReport

Run summary returned to the caller and printed by the rake task / CLI
(Key Entity "Generation Report", FR-014).

| Field | Type | Notes |
|-------|------|-------|
| `processed_count` | Integer | Endpoints written to the document. |
| `skipped` | [{ route, reason }] | Routes excluded, with reason (FR-014). |
| `warnings` | [String] | Non-fatal issues (FR-016). |
| `output_path` | String | Where the document was written. |

## Pipeline (entity flow)

```text
Rails route set
   └─ RouteCollector ──> [Route]            (filtered by Configuration)
        └─ SourceLocator ──> ControllerSource / ActionSource
             ├─ DocCommentExtractor ──> DocComment
             └─ ParamExtractor ──────> [ParamCall]
                  └─ SchemaMapper ────> Parameter.schema
        └─ OperationBuilder ──> Endpoint
   └─ DocumentBuilder ──> OpenApiDocument ──> Writer ──> file
   └─ Report ──> GenerationReport
```
