# Phase 1 Data Model: Implicit Params Detection

New and changed in-memory objects. Nothing is persisted. These extend the
feature 001/002 parameter pipeline.

## ControllerMethodWalker (new — shared)

Not a value object — a service that yields method bodies. Extracted from
`WrapperDownloadResolver`'s feature-004 recursion.

| Operation | Result |
|-----------|--------|
| `reachable_bodies(controller_class, action_node)` | An Array of method AST nodes: the action body plus every receiverless helper it reaches, recursively. |

**Rules**: Resolution uses `MethodResolver`; recursion is bounded by
`Configuration#method_resolution_depth` and cycle-guarded by a visited-set of
resolved `"file:line"` locations. An unresolvable call ends that branch.

## ImplicitParam (new)

A parameter discovered from `params` usage.

| Field | Type | Notes |
|-------|------|-------|
| `name` | String | The parameter key (a literal symbol/string from a `params` access). |

**Rules**: Produced by `ImplicitParamScanner`. Names are collected across all
reachable bodies, de-duplicated, and emitted in a stable (sorted) order. The
scanner returns only names — type and location are decided by `OperationBuilder`
(always "any", placement per the route's HTTP method).

## Configuration (changed)

| Field | Change |
|-------|--------|
| `download_resolution_depth` → `method_resolution_depth` | Renamed; same default (5) and validation (integer ≥ 1). Now bounds both wrapper-download and implicit-params recursion. |

## Parameter (reused, unchanged shape)

Implicit parameters become ordinary `Parameter` records (feature 001):

| Field | Value for an implicit parameter |
|-------|--------------------------------|
| `name` | the discovered key |
| `location` | `:query` for GET/DELETE, `:body` for POST/PUT/PATCH (mirrors `param!`) |
| `required` | `false` |
| `schema` | `{}` — the permissive "any" schema |

## Endpoint / Response / RenderResult (unchanged shape)

No structural change. `OperationBuilder` produces the same `Endpoint`; its
`parameters` / `request_body` simply include the merged implicit parameters.

## Scan & merge flow (additions in **bold**)

```text
Route ──> SourceLocator ──> controller class + ActionSource
   ├─ ParamExtractor ───────> [ParamCall]        (param! — unchanged)
   └─ **ImplicitParamScanner**
        └─ **ControllerMethodWalker.reachable_bodies(class, action_node)**
        └─ scan each body for params[:k] / params.require|permit|fetch|dig
        └─ ──> [ImplicitParam name, …]
OperationBuilder.build(route, …, param_calls:, implicit_params:):
   path params  ∪  param! params  ∪  (implicit params
        minus path names, minus param! names, minus controller/action/format)
   ──> Endpoint.parameters / request_body

WrapperDownloadResolver ── also now uses ──> **ControllerMethodWalker**
```
