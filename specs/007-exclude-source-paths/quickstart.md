# Quickstart: Exclude Endpoints by Source Path

How a developer scopes the generated document by where controllers live.

## 1. Configure the exclusions

In `config/initializers/rails_openapi_generator.rb`:

```ruby
RailsOpenapiGenerator.configure do |config|
  config.exclude_source_paths = ["vendor/"]
end
```

`exclude_source_paths` accepts:

- **strings** — matched as a substring of a controller's source file path
  (`"vendor/"` excludes any controller under a `vendor` directory);
- **regexps** — matched against the path
  (`%r{app/controllers/legacy/}`).

## 2. Generate

```sh
rake openapi:generate
```

Endpoints whose controller source file matches an entry are left out of the
document. The run report lists them under `Skipped:`:

```text
  Processed:      318 endpoints
  Skipped:        42
    - GET /vendored/widgets (controller source excluded by exclude_source_paths)
```

## 3. Combine with `route_filter`

`exclude_source_paths` works alongside the existing `route_filter` — one filters
by route, the other by where the controller is defined. Both apply:

```ruby
RailsOpenapiGenerator.configure do |config|
  config.route_filter         = ->(route) { route.path.start_with?("/api/") }
  config.exclude_source_paths = ["vendor/"]
end
```

## 4. Default

With `exclude_source_paths` unset (the default empty list), nothing is excluded
on the basis of source path — the document is unchanged.

## Acceptance smoke test

| Spec story | Quickstart step proving it |
|------------|----------------------------|
| US1 — exclude by substring | Step 2 — `"vendor/"` controllers are absent and reported skipped |
| US2 — exclude by regexp | Step 1 — a `%r{…}` entry excludes matching controllers |
