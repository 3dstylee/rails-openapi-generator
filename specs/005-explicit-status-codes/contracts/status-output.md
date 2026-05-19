# Contract: Status Code Output

How operation status codes appear in the generated document after this feature.
There is **no new output shape** — only which status code each success response
is filed under, and the absence of a body for `head` responses.

## An action with an explicit `head` status

```ruby
def update_all_projects_hidden  # POST
  # ...
  head :ok
end
```

Before — the status was guessed from the HTTP method (`POST` → `201`):

```json
"post": { "responses": { "201": { "description": "Successful response" } } }
```

After — the status is read from `head :ok`:

```json
"post": { "responses": { "200": { "description": "Successful response" } } }
```

A `PUT` action that also does `head :ok` is likewise documented under `200` —
the two are now consistent, where before the `PUT` showed `200` and the `POST`
showed `201`.

## An action with `render … status:`

```ruby
def create  # POST
  render json: project, status: :created
end
```

```json
"post": {
  "responses": {
    "201": {
      "description": "Successful response",
      "content": { "application/json": { "schema": { "type": "object", "...": {} } } }
    }
  }
}
```

The status comes from `status: :created`; the body still comes from the
`render json:` value.

## A head response has no body

A success response produced by a `head` call carries its status code and **no**
`content`:

```json
"responses": { "200": { "description": "Successful response" } }
```

`head :no_content` continues to produce `204` with no body — unchanged.

## No explicit status — unchanged

An action that sets no explicit (mappable, happy-path) status is filed under the
HTTP-method convention, exactly as before:

| HTTP method | Status |
|-------------|--------|
| GET, PUT, PATCH | 200 |
| POST | 201 |
| DELETE | 204 |

An action whose only status statement is an error status (4xx/5xx), or an
unrecognized status symbol, also falls back to the convention.

## Guarantees

- Only the documented status code (and, for `head`, the absence of a body)
  changes. Response kind, body schema, tags, vendor extensions, parameters, and
  descriptions are unchanged (FR-010).
- No controller action is executed (FR-009).
- Output is deterministic and still validates against the OpenAPI 3.1 schema
  (FR-011).
