# Contract: Implicit Params Output

How parameters discovered from `params` usage appear in the generated document.
There is **no new output shape** — implicit parameters are ordinary OpenAPI
parameters, just discovered from a new source.

## An action that reads `params[:key]`

```ruby
def create  # POST
  setting = CompanyRealEstateProjectSetting.find(params[:id])
  setting.update!(image_contact: params[:image])
  head :ok
end
```

Before — only the path parameter `id` was documented:

```json
"post": {
  "parameters": [
    { "name": "id", "in": "path", "required": true, "schema": { "type": "string" } }
  ],
  "responses": { "200": { "description": "Successful response" } }
}
```

After — `params[:image]` is discovered and added (`params[:id]` is **not**
duplicated — it is already the path parameter):

```json
"post": {
  "parameters": [
    { "name": "id", "in": "path", "required": true, "schema": { "type": "string" } }
  ],
  "requestBody": {
    "content": {
      "application/json": {
        "schema": {
          "type": "object",
          "properties": { "image": {} }
        }
      }
    }
  },
  "responses": { "200": { "description": "Successful response" } }
}
```

`image` has a permissive (`{}`, "any") schema and is optional. It is placed in
the request body because `create` is a `POST`; for a `GET`/`DELETE` action an
implicit parameter is placed as a query parameter.

## Strong-params calls

```ruby
def update  # PUT
  attrs = params.require(:project).permit(:name, :archived)
  # ...
end
```

`project`, `name`, and `archived` are each documented as parameters (the
strong-params chain is flattened).

## Parameters from helper methods

An action that reads `params` only through a helper method it calls (directly
or through a chain of helpers) still gets those keys documented on its
operation — the scan follows receiverless helper calls recursively.

## Deduplication and exclusions

- A key already declared via `rails_param` `param!` keeps its `param!`
  definition (type + constraints); the implicit version is not added.
- A key that is a path-segment parameter is documented once.
- `controller`, `action`, and `format` are never documented.
- `params[variable]` (a non-literal key) contributes nothing.

## Configuration

The recursion-depth setting is renamed (it now bounds two scans):

```ruby
RailsOpenapiGenerator.configure do |config|
  config.method_resolution_depth = 5 # was: download_resolution_depth
end
```

## Guarantees

- Additive — path parameters, `param!` parameters, response bodies, tags, and
  all other operation content are unchanged; only newly discovered implicit
  parameters are added (FR-010).
- No controller action or helper method is executed (FR-009).
- Output is deterministic — implicit parameters are emitted in a stable order —
  and still validates against the OpenAPI 3.1 schema (FR-011).
