# Contract: Response Output

How response bodies appear in the generated OpenAPI document after this feature.
This refines — it does not replace — the feature 001 contracts; the library API,
rake task, and CLI signatures are unchanged.

## Operation `responses` object

Before this feature every operation carried a fixed placeholder:

```json
"responses": { "200": { "description": "Successful response" } }
```

After this feature each operation carries one success response, filed under a
status code derived from the HTTP method, with a body schema when one can be
determined.

### Read / update operation with a determinable body (GET, PUT, PATCH)

```json
"responses": {
  "200": {
    "description": "Successful response",
    "content": {
      "application/json": {
        "schema": {
          "type": "object",
          "properties": {
            "id": {},
            "name": {},
            "author": { "type": "object", "properties": { "id": {} } }
          }
        }
      }
    }
  }
}
```

Leaf properties read from jbuilder value expressions are permissive (`{}`);
properties read from a literal `render json:` are typed.

### Collection operation

```json
"responses": {
  "200": {
    "description": "Successful response",
    "content": {
      "application/json": {
        "schema": {
          "type": "array",
          "items": { "type": "object", "properties": { "id": {} } }
        }
      }
    }
  }
}
```

### Creation operation (POST)

Filed under `201`; body schema attached when determinable.

```json
"responses": {
  "201": {
    "description": "Successful response",
    "content": { "application/json": { "schema": { "type": "object", "properties": { "id": { "type": "integer" } } } } }
  }
}
```

### No-content operation (DELETE, or explicit `head :no_content`)

Filed under `204`, no `content`:

```json
"responses": { "204": { "description": "Successful response" } }
```

### Undeterminable response

When neither a jbuilder template nor a literal `render json:` yields a shape,
the operation keeps a `content`-less success entry under its status code, and
the run report records a warning naming the operation:

```json
"responses": { "200": { "description": "Successful response" } }
```

## Guarantees

- The document continues to validate against the OpenAPI 3.1 schema with
  response bodies included (FR-009).
- Output is deterministic for unchanged input — property order within a schema
  is stable (FR-010).
- No host controller action is executed and no HTTP request is made (FR-008).
- Routes, parameters, summaries, descriptions, and tags are byte-for-byte
  unchanged from feature 001 output; only each operation's `responses` object
  changes (FR-012).

## Status code mapping

| HTTP method | Success status |
|-------------|----------------|
| GET, PUT, PATCH | 200 |
| POST | 201 |
| DELETE (or explicit no-content) | 204 |

## Precedence

For one action, when both sources are present, a literal `render json:` in the
action body wins over the jbuilder view template (FR-002).
