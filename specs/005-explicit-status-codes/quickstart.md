# Quickstart: Explicit Success Status Codes

What changes for a developer once this feature ships. There is **nothing new to
do** — accurate status codes appear automatically on the next run.

## 1. The problem it solves

Two actions that both end with `head :ok` were documented with different status
codes, because the status was guessed from the HTTP method:

```ruby
def update_all_projects_hidden  # POST → was documented 201
  head :ok
end

def remove_real_estate          # PUT  → was documented 200
  head :ok
end
```

## 2. What's new

The generator now reads the status the action actually sets. Both actions above
are documented under **`200`** — the status `head :ok` produces:

```json
"responses": { "200": { "description": "Successful response" } }
```

It reads the status from:

- `head :symbol` / `head <integer>` — e.g. `head :ok` → 200, `head :created` → 201
- the `status:` option of `render` — e.g. `render json: x, status: :created` → 201

A `head` response is documented with **no body**.

## 3. What stays the same

- An action that sets **no explicit status** still uses the HTTP-method
  convention — `GET`/`PUT`/`PATCH` → 200, `POST` → 201, `DELETE` → 204.
- **Error statuses are ignored.** An early `render status: :unprocessable_entity`
  guard does not affect the documented success status.
- Only the **status code** changes — response bodies, tags, `x-` marks, and
  descriptions are exactly as before.

## Acceptance smoke test

| Spec story | Quickstart step proving it |
|------------|----------------------------|
| US1 — explicit status documented | Step 2 — `head :ok` → 200 on both POST and PUT |
| US2 — head has no body | Step 2 — the `head` response shows no `content` |
| US3 — method-convention fallback | Step 3 — no explicit status → unchanged convention |
