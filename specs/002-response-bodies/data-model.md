# Phase 1 Data Model: Happy-Path Response Bodies

New and changed in-memory objects. Nothing is persisted; the OpenAPI document
remains the only output artifact. These extend the feature 001 pipeline.

## ViewTemplate

A located jbuilder view file for an action.

| Field | Type | Notes |
|-------|------|-------|
| `file_path` | String | Absolute path to a `.json.jbuilder` file. |
| `controller` | String | Controller key the template belongs to. |
| `action` | String | Action the template renders for. |

**Rules**: Produced by `ViewLocator` from the Rails view-path convention or an
explicit literal `render` in the action. `nil` when no template is found.

## RenderCall

A statically resolved literal `render json:` found in an action body.

| Field | Type | Notes |
|-------|------|-------|
| `value` | resolved Ruby value / `UNRESOLVED` | Literal hash/array/scalar from the `json:` argument. |
| `fully_resolved` | Boolean | False when the argument is non-literal (FR-014). |

**Rules**: Extracted by `RenderExtractor` from the action's Ripper AST using the
shared `LiteralEvaluator`. A non-literal `render json:` yields `fully_resolved =
false` and is not used to build a schema.

## ResponseSchema

The structured shape of a response body, expressed as an OpenAPI schema Hash.

| Field | Type | Notes |
|-------|------|-------|
| `shape` | Hash | An OpenAPI schema: `object` with `properties`, or `array` with `items`. |
| `determinable` | Boolean | False when no source (template or literal) yielded a shape. |

**Rules**:
- `object` shape → `{ "type" => "object", "properties" => { … } }`.
- `array` shape → `{ "type" => "array", "items" => { … } }`.
- Leaf properties from jbuilder value expressions are permissive (`{}`); leaf
  properties from literals are typed (FR-013, research R3).
- Nested `json.* do … end` blocks and partials produce nested object schemas.

## Response

The success response of one operation (Key Entity "Response").

| Field | Type | Notes |
|-------|------|-------|
| `status` | Integer | `200`, `201`, or `204` (research R5). |
| `body` | ResponseSchema / nil | `nil` for `204` and for undeterminable responses. |
| `description` | String | Human-readable, e.g. `"Successful response"`. |

**Rules**: Built by `ResponseBuilder`. A literal `RenderCall` takes precedence
over a `ViewTemplate` when both exist for an action (FR-002, edge case "both
sources present"). When neither yields a shape, `body` is `nil` and the
operation is reported as having an undeterminable response (FR-007).

## Endpoint (changed)

The feature 001 `Endpoint` gains one field.

| New field | Type | Notes |
|-----------|------|-------|
| `response` | Response | The success response for this operation. |

All existing fields (`http_method`, `path`, `summary`, `description`,
`parameters`, `request_body`, `operation_id`, `tag`) are unchanged.

## OpenApiDocument (changed)

Each operation's `responses` object changes from a fixed placeholder to a
real success response:

```text
"responses": {
  "<status>": {
    "description": "Successful response",
    "content": {
      "application/json": { "schema": <ResponseSchema.shape> }
    }
  }
}
```

- A `204` response has no `content`.
- An undeterminable response keeps a `content`-less success entry under the
  status code (valid OpenAPI), matching prior behavior for those operations.

## GenerationReport (unchanged shape)

No new fields. Undeterminable responses add entries to the existing `warnings`
list (FR-007), e.g. `"GET /api/things: response shape could not be determined"`.

## Pipeline (entity flow — additions in **bold**)

```text
Route ──> SourceLocator ──> ControllerSource / ActionSource
   ├─ DocCommentExtractor ──> DocComment
   ├─ ParamExtractor ───────> [ParamCall]      (now via LiteralEvaluator)
   ├─ **RenderExtractor** ──> **RenderCall**   (via LiteralEvaluator)
   └─ **ViewLocator** ──────> **ViewTemplate**
        └─ **JbuilderParser** ──> **ResponseSchema**
   **ResponseBuilder** (RenderCall ▸ ViewTemplate) ──> **Response**
OperationBuilder ──> Endpoint (now carries response)
DocumentBuilder ──> OpenApiDocument (operations carry real responses)
```
