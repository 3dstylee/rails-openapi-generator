# 3. The output contract

What does a successful run produce? This chapter is about the *promise* — the shape and properties of the document we write to disk. Every choice in the rest of the code serves these promises.

## The promise

One file. JSON or YAML. Contains an [OpenAPI 3.1](https://spec.openapis.org/oas/v3.1.0) document. Byte-identical when the source is unchanged.

That's it. Three properties. They're load-bearing in different ways, and we'll go through them in order.

## OpenAPI 3.1, the slice we emit

OpenAPI 3.1 is a vast spec. We emit a tiny corner of it. [`DocumentBuilder`](../lib/rails_openapi_generator/document_builder.rb) is the source of truth — anything that ends up in the document passes through this file.

The skeleton is six keys:

```ruby
document = {
  "openapi" => OPENAPI_VERSION,
  "info" => info
}
tags = tags(endpoints)
document["tags"] = tags unless tags.empty?
document["paths"] = paths(endpoints)
```

— [`document_builder.rb:17-24`](../lib/rails_openapi_generator/document_builder.rb)

We emit `openapi`, `info`, `tags`, and `paths`. We do not emit `components`, `security`, `servers`, `webhooks`, or any of the other top-level keys. That's a load-bearing limitation, not taste — we don't have a way to discover those things from source.

Inside an operation, we emit `operationId`, `tags`, `summary`, `description`, `parameters`, `requestBody`, `responses`, and the two custom extensions `x-renders-html` / `x-sends-file` (chapter 7):

```ruby
result = { "operationId" => endpoint.operation_id }
tags = operation_tags(endpoint)
result["tags"]        = tags unless tags.empty?
result["summary"]     = endpoint.summary if endpoint.summary
result["description"] = endpoint.description if endpoint.description
result.merge!(kind_extensions(endpoint.response))

parameters = endpoint.parameters.reject { |param| param.location == :body }
result["parameters"]  = sorted_parameters(parameters) unless parameters.empty?
result["requestBody"] = endpoint.request_body if endpoint.request_body
result["responses"]   = responses(endpoint.response)
```

— [`document_builder.rb:83-95`](../lib/rails_openapi_generator/document_builder.rb)

Notice the `unless empty?` and `if endpoint.summary` clauses. We *omit* keys when their values are empty or absent, rather than emitting `summary: nil` or `parameters: []`. That choice serves the third promise — byte-identical output. Two ways to spell "no parameters" would produce two outputs from the same input.

## Determinism, the hardest promise

The third promise — byte-identical output across runs of unchanged source — is the one we work the hardest for. The README states it bluntly:

> Re-runs are byte-identical given the same source.

This sounds obvious. It is not. Ruby Hash iteration is insertion-order-stable, but the *insertion order* of a hash depends on Hash#each, on `group_by`, on filesystem `Dir.glob`, on the order we visit routes. Any non-deterministic source poisons the output.

We address it in three layers.

**Sort at every aggregation point.** Whenever we hold a collection and are about to emit it, we sort. Look at how paths are built:

```ruby
def paths(endpoints)
  grouped = Hash.new { |hash, key| hash[key] = {} }
  endpoints.sort_by { |endpoint| [endpoint.path, endpoint.http_method] }.each do |endpoint|
    grouped[openapi_path(endpoint.path)][endpoint.http_method.downcase] = operation(endpoint)
  end
  grouped.keys.sort.to_h do |path|
    [path, sort_by_method(grouped[path])]
  end
end
```

— [`document_builder.rb:61-71`](../lib/rails_openapi_generator/document_builder.rb)

Two sorts. First, the endpoints; second, the paths Hash by key. The path-level sort is alphabetical (lexical). The method-level sort is `METHOD_ORDER = %w[get post put patch delete]` — meaningful to a human reader rather than alphabetical.

Properties inside a request body? Sorted:

```ruby
schema = { "type" => "object", "properties" => sort_properties(properties) }
```

— [`operation_builder.rb:122`](../lib/rails_openapi_generator/operation_builder.rb)

Parameters inside an operation? Sorted with a stable key:

```ruby
LOCATION_ORDER = { path: 0, query: 1, body: 2 }.freeze
# ...
parameters
  .sort_by { |param| [LOCATION_ORDER.fetch(param.location, 9), param.name] }
```

— [`document_builder.rb:8, 152-153`](../lib/rails_openapi_generator/document_builder.rb)

`oneOf` arrays in multi-status responses? Sorted by canonical JSON:

```ruby
{ "oneOf" => unique.sort_by { |schema| JSON.generate(schema) } }
```

— [`response_builder.rb:207`](../lib/rails_openapi_generator/response_builder.rb)

The pattern: sort by something that's a pure function of the data, never by something that could vary across runs.

**Stable upstream.** Sorting at the end isn't enough if an earlier stage produces non-deterministic intermediate shape. [`RouteCollector`](../lib/rails_openapi_generator/route_collector.rb) explicitly sorts before returning:

```ruby
routes.sort_by { |route| [route.path, route.http_method] }
```

— [`route_collector.rb:27`](../lib/rails_openapi_generator/route_collector.rb)

— even though we sort again later. Sorting twice is cheap; debugging which stage introduced non-determinism is not.

**No filesystem orderings leak through.** `Dir.glob` returns OS-dependent ordering. We don't trust it. When the view locator searches for an HTML view:

```ruby
path = Dir.glob(File.join(@views_root, "#{name}.html.*")).min
```

— [`view_locator.rb:79`](../lib/rails_openapi_generator/view_locator.rb)

`.min` is a deterministic choice — alphabetically first — rather than `.first`.

> **Aside: why determinism matters this much.**
> Two consumers: humans diffing the output in a pull request, and CI checks that grep for breaking changes. Both break when the output reorders for no reason. A docs-only PR shouldn't show 200 unrelated lines flipped. The integration suite enforces this with [`spec/integration/determinism_spec.rb`](../spec/integration/determinism_spec.rb), which runs `generate` twice in a row and `eq`s the strings.

## The format choice — JSON vs YAML

The user picks JSON (default) or YAML via [`Configuration#format`](../lib/rails_openapi_generator/configuration.rb). The default isn't arbitrary:

```ruby
when :yaml then YAML.dump(document)
else "#{JSON.pretty_generate(document)}\n"
```

— [`writer.rb:25-27`](../lib/rails_openapi_generator/writer.rb)

JSON wins by default because (a) it has no ambiguity around YAML's "Norway problem" (the literal string `"no"` becoming `false`) and (b) JSON is the OpenAPI ecosystem's lingua franca. YAML is a convenience for humans editing the file by hand — a use case we don't otherwise design around.

We also emit a trailing newline on JSON output. POSIX-friendly; required by some CI linters.

## Vendor extensions

OpenAPI lets you add `x-` keys anywhere. We use exactly two:

| Key | Where | Meaning |
|---|---|---|
| `x-renders-html` | operation | this endpoint serves HTML, not JSON |
| `x-sends-file` | operation | this endpoint streams a file download |

We added them because reviewers asked, "How do I find every non-JSON endpoint?" and grepping for `text/html` content types is fragile (some viewers normalize content types). A flag on the operation is more direct. See [`document_builder.rb:99-110`](../lib/rails_openapi_generator/document_builder.rb).

## What we do *not* promise

- We don't promise the document is *complete*. If your action does `render YourPresenter.new(...).to_json`, we will emit a 200 entry with an empty body schema and a warning. The output reflects what we could read, not what your endpoint truly returns.
- We don't promise schemas are *narrow*. A property whose value comes from a method call gets `{}` — meaning "any JSON value." Loose, but correct.
- We don't promise idempotence across versions. Output format may change between minor versions of this gem; see the [CHANGELOG](../CHANGELOG.md).

These are deliberate. The alternative — promising fidelity we can't deliver — would force runtime execution, which is the road rswag walks and we don't.

## Try it yourself

Generate the document for the dummy app twice:

```sh
bundle exec rspec spec/integration/determinism_spec.rb
```

It passes. Now go to [`document_builder.rb:127-128`](../lib/rails_openapi_generator/document_builder.rb) and swap `properties.sort.to_h` for `properties` (no sort). Run the determinism spec again. Watch it fail — but also fail *intermittently*, not every run. Why is it intermittent? (Hint: small hashes in Ruby happen to iterate insertion order, which sometimes happens to be sorted. The bug is real but hides on small inputs.) Revert when you're done.
