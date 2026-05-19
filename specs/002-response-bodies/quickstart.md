# Quickstart: Happy-Path Response Bodies

What changes for a developer once this feature ships. There is **nothing new to
install or configure** — response bodies appear automatically on the next run.

## 1. Generate as before

```sh
rake openapi:generate
```

## 2. What's new in the output

Each operation's `responses` section now describes the success body.

### jbuilder-backed endpoints

Given `app/views/api/users/index.json.jbuilder`:

```ruby
json.array! @users do |user|
  json.id user.id
  json.name user.name
end
```

the generated `GET /api/users` operation gains:

```json
"responses": {
  "200": {
    "description": "Successful response",
    "content": {
      "application/json": {
        "schema": {
          "type": "array",
          "items": { "type": "object", "properties": { "id": {}, "name": {} } }
        }
      }
    }
  }
}
```

Field **names and nesting** are recovered; leaf **types** are left open (`{}`)
when read from a jbuilder value expression.

### Literal-render endpoints

Given an action with:

```ruby
def create
  # ...
  render json: { id: user.id, status: "created" }
end
```

`POST` operations are filed under `201`, and a literal `render json:` is typed
precisely:

```json
"responses": {
  "201": {
    "content": { "application/json": { "schema": {
      "type": "object",
      "properties": { "id": {}, "status": { "type": "string" } }
    } } }
  }
}
```

A literal `render json:` in the action wins over a view template if both exist.

## 3. Status codes

| Endpoint kind | Status |
|---------------|--------|
| Reads / updates (GET, PUT, PATCH) | 200 |
| Creation (POST) | 201 |
| Deletion / no content (DELETE, `head :no_content`) | 204 (no body) |

## 4. When a response can't be determined

Endpoints whose response shape can't be read statically — non-literal
`render json:`, serializer-based responses, unlocatable partials — still appear
with a valid success response (no body schema), and the run report names them:

```text
  Warnings:  3
    - GET /api/legacy_report: response shape could not be determined
```

## 5. Preview

Re-render the docs to see bodies in Redoc/Swagger UI:

```sh
npx @redocly/cli build-docs doc/openapi.json -o doc/openapi.html
```

## Acceptance smoke test

| Spec story | Quickstart step proving it |
|------------|----------------------------|
| US1 — success response body | Steps 2 — jbuilder and literal endpoints show a body schema |
| US2 — graceful when undeterminable | Step 4 — endpoint still valid, named in the report |
| US3 — conventional status code | Step 3 — 200 / 201 / 204 by endpoint kind |
