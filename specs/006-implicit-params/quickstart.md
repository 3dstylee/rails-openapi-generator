# Quickstart: Implicit Params Detection

What changes for a developer once this feature ships. There is **nothing new to
do** — implicitly-used parameters are detected automatically on the next run.

## 1. The problem it solves

An action reads request input straight off `params`, with no `rails_param`
declaration:

```ruby
def create
  setting = CompanyRealEstateProjectSetting.find(params[:id])
  setting.update!(image_contact: params[:image])
  head :ok
end
```

`params[:image]` was invisible — the operation looked like it took no body.

## 2. What's new

The generator now scans the action (and the helper methods it calls) for
`params` usage and documents each key it finds:

- `params[:key]` / `params["key"]`
- `params.require(:key)`, `params.permit(:a, :b)`, `params.fetch(:key)`,
  `params.dig(:a, :b)`

For the `create` above, `image` is added as a request-body property (it's a
`POST`); `params[:id]` is *not* duplicated — it's already the path parameter.

Discovered parameters have a permissive **"any"** schema — `params` access
carries no type information.

## 3. What it does NOT do

- It does not name a parameter from a non-literal key — `params[some_variable]`
  is skipped.
- It does not override `rails_param`. A key declared with `param!` keeps its
  typed, constrained definition; the implicit version is dropped.
- It never documents Rails-internal keys (`controller`, `action`, `format`).
- It never executes code; a helper that can't be located statically just ends
  that branch of the scan.

## 4. Configuration

The recursion-depth setting is renamed (it now bounds both wrapper-download and
implicit-params scanning):

```ruby
RailsOpenapiGenerator.configure do |config|
  config.method_resolution_depth = 5 # previously download_resolution_depth
end
```

## Acceptance smoke test

| Spec story | Quickstart step proving it |
|------------|----------------------------|
| US1 — `params[:key]` documented | Step 2 — `image` appears as a parameter |
| US2 — strong-params documented | Step 2 — `require`/`permit`/`fetch`/`dig` keys appear |
| US3 — params via helpers | Step 2 — helper-read keys appear on the action |
