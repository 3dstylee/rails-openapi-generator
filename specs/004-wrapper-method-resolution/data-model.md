# Phase 1 Data Model: Wrapper Method Resolution for File Downloads

New and changed in-memory objects. Nothing is persisted. These extend the
feature 003 classification pipeline.

## ResolvedMethod (new)

The located definition of a method reached during wrapper resolution.

| Field | Type | Notes |
|-------|------|-------|
| `name` | String | The method name. |
| `node` | Array | The method's `def` Ripper AST node. |
| `location` | String | `"file:line"` — the resolved source location, used as the cycle-guard identity. |

**Rules**: Produced by `MethodResolver`. `nil` is returned (not a
`ResolvedMethod`) when the method cannot be located — unknown name, a method
defined outside the application, or a `source_location` of nil.

## Configuration (changed)

| New field | Type | Default | Notes |
|-----------|------|---------|-------|
| `download_resolution_depth` | Integer | `5` | Maximum wrapper-chain depth followed during resolution (FR-005). |

**Validation**: `download_resolution_depth` must be an integer `>= 1`;
`Configuration#validate!` raises `ConfigurationError` otherwise.

## Resolution run (transient — not a stored entity)

While resolving one action, `WrapperDownloadResolver` carries:

| Item | Type | Notes |
|------|------|-------|
| `depth` | Integer | Current recursion depth; resolution stops when it reaches `download_resolution_depth`. |
| `visited` | Set of String | Resolved `"file:line"` locations already inspected — the cycle guard (FR-006). |

These live only for the duration of one action's resolution; they are not part
of any persisted or returned object.

## RenderResult / Classification / Response (unchanged shape)

No structural change. A wrapper-resolved download produces the same outcome as a
direct one: `RenderClassifier` returns a `Classification` with
`kind: :file_download`, and the rest of the pipeline (`ResponseBuilder`,
`OperationBuilder`, `DocumentBuilder`, `GenerationReport`) treats it identically
to a directly detected download (FR-012) — `application/octet-stream` response,
`"File Downloads"` tag, `x-sends-file` extension, and inclusion in the
file-download count.

## Classification flow (additions in **bold**)

```text
RenderExtractor ──> RenderResult (direct send_file? render? html?)
RenderClassifier.classify(route, render_result, controller_class, action_node):
   render json:       → :json
   send_file direct   → :file_download
   render html:       → :html_page
   view lookup        → :json / :html_page
   else:
     **WrapperDownloadResolver.download?(controller_class, action_node)**
       → resolves receiverless calls via **MethodResolver**, recursively,
         bounded by Configuration#download_resolution_depth, cycle-guarded
       → true  → :file_download
       → false → :undeterminable
```
