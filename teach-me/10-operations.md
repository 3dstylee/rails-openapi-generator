# 10. Operational concerns

A tool that runs in CI has obligations beyond producing correct output. It must fail in a way humans can act on. It must not crash the build because one controller is weird. It must tell the user what it skipped and why.

This chapter is about three things: the run report, the resilience policy, and the writer.

## The run report

[`GenerationReport`](../lib/rails_openapi_generator/report.rb) accumulates everything worth telling the user. It's threaded through the entire pipeline (chapter 5) and ends as a printed summary:

```ruby
def summary
  lines = []
  lines << "OpenAPI document written to #{output_path}" if output_path
  lines << "  Processed:      #{processed_count} endpoints"
  lines << "  HTML pages:     #{html_page_count} endpoints"
  lines << "  File downloads: #{file_download_count} endpoints"
  lines << "  Skipped:        #{skipped.size}"
  skipped.each do |entry|
    route = entry[:route]
    lines << "    - #{route.http_method} #{route.path} (#{entry[:reason]})"
  end
  lines << "  Warnings:       #{warnings.size}"
  warnings.each { |message| lines << "    - #{message}" }
  lines.join("\n")
end
```

— [`report.rb:34-48`](../lib/rails_openapi_generator/report.rb)

Two categories of non-success: **skipped** and **warnings**, and they mean different things.

A *skip* is a route we deliberately did not document, with a reason: a redirect route with no controller, or a controller excluded by config. The route isn't in the output, and that's correct.

A *warning* is a route we *did* document but couldn't fully understand: a `param!` with a non-literal argument, a response shape we couldn't determine, a malformed sidecar. The endpoint *is* in the output, possibly with a permissive schema, and the warning tells the user where to look if they want richer docs.

The distinction matters to the user reading the summary. "Skipped" means "I left this out — was that right?" "Warning" means "I included this but guessed — can you help me out?"

## `success?` always returns true

The most opinionated method in the gem:

```ruby
def success?
  true
end
```

— [`report.rb:29-31`](../lib/rails_openapi_generator/report.rb)

A run *always* completes. There is no failure mode for "I couldn't understand your code." Per-endpoint problems degrade to warnings; the document is still produced; the exit code is still 0.

This is a deliberate, somewhat aggressive choice. The alternative — exit non-zero if any warning — would make the gem unusable in CI on any real app, because every real app has *some* action we can't fully read. We decided that a partial document with honest warnings beats a hard failure.

Configuration errors are the exception (chapter 9): those raise, before any work, because they're fixable mistakes the user must address. But once we've started processing endpoints, nothing the *user's code* contains can stop us.

## The resilience policy, made concrete

Chapter 2 introduced "warn, never raise." Here's what it looks like across the codebase. The pattern repeats:

**At the top of the per-route loop**, a catch-all turns any unexpected error into a warning plus a minimal operation:

```ruby
rescue StandardError => e
  @report.warn("#{route.http_method} #{route.path}: #{e.message}")
  @report.processed_count += 1
  @operation_builder.build(route)
end
```

— [`generator.rb:97-101`](../lib/rails_openapi_generator/generator.rb)

**In the resolvers**, the same shape guards against malformed input. `RescueFromResolver`:

```ruby
def resolve(controller_class)
  return [] if controller_class.nil?
  return @cache[controller_class] if @cache.key?(controller_class)

  @cache[controller_class] = build_handlers(controller_class)
rescue StandardError
  @cache[controller_class] = []
end
```

— [`rescue_from_resolver.rb:31-38`](../lib/rails_openapi_generator/rescue_from_resolver.rb)

A controller whose `rescue_handlers` are weird returns `[]` (no extra error responses), not a crash.

**In the constant resolver**, a constant that can't be loaded — or whose value isn't schema-compatible — returns the sentinel, never raises:

```ruby
def lookup_and_filter(qualified_name)
  value = Object.const_get(qualified_name, true)
  schema_compatible?(value) ? value : LiteralEvaluator::UNRESOLVED
rescue StandardError, LoadError
  LiteralEvaluator::UNRESOLVED
end
```

— [`constant_resolver.rb:33-38`](../lib/rails_openapi_generator/constant_resolver.rb)

Note `LoadError` is caught alongside `StandardError` — `const_get` can trigger autoloading, which can fail with a `LoadError` (not a `StandardError` subclass). Catching only `StandardError` would leak that. This is the kind of bug you only find by running against a real app with a broken autoload.

**In the sidecar loader**, a malformed JSON file warns and falls through:

```ruby
def parse_sidecar(path)
  JSON.parse(File.read(path))
rescue JSON::ParserError => e
  @report&.warn("schema sidecar `#{path}` failed to parse: #{e.message}")
  nil
end
```

— [`schema_sidecar_loader.rb:61-67`](../lib/rails_openapi_generator/schema_sidecar_loader.rb)

This one is narrower — it catches `JSON::ParserError`, not all errors — because a malformed sidecar is an *expected* failure (the user typo'd their JSON), and we want a specific, helpful message. The `@report&.warn` uses the safe-navigation operator because the loader can be constructed without a report in unit tests.

The discipline: catch broadly at boundaries where any failure should degrade gracefully; catch narrowly where you can name the expected failure and give a better message.

> **Aside: the danger of broad rescues.**
> A `rescue StandardError` that swallows everything is usually a code smell — it can hide real bugs. We accept it here because of the domain: we run untrusted user code structures through fragile AST matching, and the *product requirement* is "never crash the user's build." But every broad rescue in this gem also calls `@report.warn` — the error is surfaced, not silenced. That's the line between resilience and negligence. A swallowed error with no warning would be a bug. The resilience integration specs ([`spec/integration/resilience_spec.rb`](../spec/integration/resilience_spec.rb), [`response_resilience_spec.rb`](../spec/integration/response_resilience_spec.rb)) exist to guard exactly this.

## The writer

The last stage. [`Writer`](../lib/rails_openapi_generator/writer.rb) serializes the document hash to disk:

```ruby
def write(document)
  path = File.expand_path(@configuration.output_path)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, serialize(document))
  path
end

def serialize(document)
  case @configuration.format
  when :yaml then YAML.dump(document)
  else "#{JSON.pretty_generate(document)}\n"
  end
end
```

— [`writer.rb:15-28`](../lib/rails_openapi_generator/writer.rb)

`mkdir_p` creates the output directory if it doesn't exist — we already validated it's writable in `Configuration#validate!`, so this won't fail. `write` returns the absolute path, which the generator stores on the report so the summary can print "written to /abs/path".

The trailing `"\n"` on JSON output is the small detail from chapter 3 — a POSIX courtesy, and it makes `git diff` happier.

`serialize` is public and separate from `write` so tests can assert on the string without touching the filesystem. A small interface decision that pays off in test speed.

## Performance, briefly

The gem runs once and exits, so we don't optimize hard. But two caches earn their keep:

- `YardParser` caches one parsed AST per file ([`yard_parser.rb:22`](../lib/rails_openapi_generator/yard_parser.rb)). A controller with ten actions is parsed once, not ten times.
- `ConstantResolver` and `JbuilderParser` and `SchemaSidecarLoader` each cache lookups for the run's lifetime.

These matter because the resolvers (chapter 8) re-traverse the same controller files repeatedly — a shared cache turns O(routes × ancestors) parses into O(files). There's a [`performance_spec.rb`](../spec/integration/performance_spec.rb) that asserts a generation run stays under a time budget, so a regression that defeats the cache gets caught.

## Try it yourself

Run the generator on the dummy app and read the printed summary:

```sh
bundle exec rails-openapi-generator --rails-root spec/fixtures/dummy --output tmp/dummy.json
```

You should see a non-zero "Skipped" count (the `legacy` redirect route) and possibly some warnings (the `api/orphan` route points at a controller that doesn't exist). Find those two routes in [`spec/fixtures/dummy/config/routes.rb`](../spec/fixtures/dummy/config/routes.rb) — they're commented as deliberate resilience exercises.

Then introduce a syntax error into one dummy controller (an unclosed `def`). Regenerate. Does the run still complete? Which route gets a warning? Does the *rest* of the document still get produced? (This is the whole point of `success? == true`.) Revert when done.
