# 9. Wiring it to Rails

A gem is dead code until something invokes it. This chapter is about the three doorways into the generator — the rake task, the CLI, and the programmatic API — plus the configuration object they all share, and the railtie that registers the rake task.

These files are small and unglamorous. They're worth a chapter anyway, because *how a tool is invoked* shapes how people adopt it.

## The configuration object

Everything starts here. [`Configuration`](../lib/rails_openapi_generator/configuration.rb) is a plain settings bag with defaults:

```ruby
def initialize
  @output_path  = DEFAULT_OUTPUT_PATH       # "doc/openapi.json"
  @title        = nil
  @api_version  = "1.0.0"
  @route_filter = nil
  @format       = nil
  @method_resolution_depth = DEFAULT_METHOD_RESOLUTION_DEPTH  # 5
  @exclude_source_paths = []
end
```

— [`configuration.rb:14-22`](../lib/rails_openapi_generator/configuration.rb)

Sensible defaults are a feature. A user who runs the gem with zero configuration gets `doc/openapi.json`, title from the app name, version `1.0.0`. The gem works out of the box.

The module-level singleton lets a host app configure once in an initializer:

```ruby
def configuration
  @configuration ||= Configuration.new
end

def configure
  yield configuration
  configuration
end
```

— [`rails_openapi_generator.rb:40-47`](../lib/rails_openapi_generator.rb)

So in `config/initializers/rails_openapi_generator.rb`:

```ruby
RailsOpenapiGenerator.configure do |config|
  config.title = "My Store API"
  config.route_filter = ->(route) { route.path.start_with?("/api/") }
end
```

This is the standard Ruby "configure block" pattern. We chose it because Rails developers already know it — `Rails.application.configure`, `Rspec.configure`, every gem they use. Familiarity over novelty.

### `format` inference

One nicety. The user usually only sets `output_path`. The format follows from the extension:

```ruby
def format
  @format || infer_format
end

def infer_format
  case File.extname(output_path.to_s).downcase
  when ".yaml", ".yml" then :yaml
  else :json
  end
end
```

— [`configuration.rb:35-37, 68-73`](../lib/rails_openapi_generator/configuration.rb)

`output_path = "doc/api.yaml"` → YAML, no extra flag. Set `format` explicitly only when you want to override.

### `validate!` — fail loud, fail early

Configuration is the *one* place we deliberately raise rather than warn:

```ruby
def validate!
  unless SUPPORTED_FORMATS.include?(format)
    raise ConfigurationError, "format must be one of #{SUPPORTED_FORMATS.inspect}, got #{format.inspect}"
  end

  raise ConfigurationError, "output_path must be set" if output_path.nil? || output_path.to_s.strip.empty?

  unless writable_destination?
    raise ConfigurationError,
          "output_path directory is not writable: #{File.dirname(File.expand_path(output_path))}"
  end
  # ... and two more checks ...
end
```

— [`configuration.rb:40-64`](../lib/rails_openapi_generator/configuration.rb)

Why raise here, when the rest of the gem warns? Because configuration errors are *the user's mistake before any work happens*, and continuing would mean writing a document to an unwritable path, then failing anyway — wasting the whole run. The earlier you fail on a misconfiguration, the kinder. Per-endpoint problems are different: there, continuing lets us produce a useful partial document. Chapter 10 makes that contrast precise.

The `writable_destination?` check walks up to the nearest existing ancestor, because the output directory may not exist yet — we'll create it, but only if we can:

```ruby
def writable_destination?
  dir = File.dirname(File.expand_path(output_path))
  dir = File.dirname(dir) until File.exist?(dir) || dir == File.dirname(dir)
  File.directory?(dir) && File.writable?(dir)
end
```

— [`configuration.rb:76-80`](../lib/rails_openapi_generator/configuration.rb)

### `exclude_source_paths`

The one filter that operates on controller *source paths* rather than routes:

```ruby
def source_excluded?(path)
  return false if path.nil?

  Array(exclude_source_paths).any? do |pattern|
    pattern.is_a?(Regexp) ? pattern.match?(path) : path.include?(pattern.to_s)
  end
end
```

— [`configuration.rb:26-32`](../lib/rails_openapi_generator/configuration.rb)

Strings match by substring, Regexps by pattern. We support both because a user excluding `"vendor/"` shouldn't have to write a regex, but a user excluding `app/controllers/legacy/.*` benefits from one. This is taste — we could have required regexps for everything. Substring-by-default is friendlier.

`route_filter` (a lambda over routes) and `exclude_source_paths` (over source files) are separate knobs because they answer different questions: "which URLs do I document?" vs. "which controller files do I trust?". A legacy controller may serve current routes.

## The railtie

[`Railtie`](../lib/rails_openapi_generator/railtie.rb) does one thing: register the rake task with the host app.

```ruby
class Railtie < Rails::Railtie
  rake_tasks do
    load File.expand_path("../tasks/rails_openapi_generator.rake", __dir__)
  end
end
```

— [`railtie.rb:5-9`](../lib/rails_openapi_generator/railtie.rb)

And it loads only when Rails is present — guarded back in the entry point:

```ruby
require_relative "rails_openapi_generator/railtie" if defined?(Rails::Railtie)
```

— [`rails_openapi_generator.rb:57`](../lib/rails_openapi_generator.rb)

That guard matters. The gem can be `require`'d outside Rails — in the unit tests, for instance, which test individual classes without booting a Rails app. The railtie only attaches when there's a Rails to attach to.

## The rake task

The most common invocation. [`lib/tasks/rails_openapi_generator.rake`](../lib/tasks/rails_openapi_generator.rake):

```ruby
namespace :openapi do
  desc "Generate an OpenAPI document for all application endpoints"
  task generate: :environment do
    configuration = RailsOpenapiGenerator.configuration
    configuration.output_path = ENV["OUTPUT"] if ENV["OUTPUT"]
    configuration.format      = ENV["FORMAT"].to_sym if ENV["FORMAT"]

    report = RailsOpenapiGenerator::Generator.new(configuration).generate
    puts report.summary
  end
end
```

— [`lib/tasks/rails_openapi_generator.rake`](../lib/tasks/rails_openapi_generator.rake)

`task generate: :environment` — the `:environment` dependency boots the full Rails app first, so `Rails.application.routes` is available. That's the load-bearing part: we cannot collect routes without a booted app.

`ENV["OUTPUT"]` and `ENV["FORMAT"]` let a user override per-run without editing the initializer:

```sh
bundle exec rake openapi:generate OUTPUT=tmp/openapi.yaml FORMAT=yaml
```

These read from the singleton `configuration`, so they layer on top of whatever the initializer set.

## The CLI

For users who don't want a rake task — CI scripts, makefiles. [`CLI`](../lib/rails_openapi_generator/cli.rb) parses args, boots Rails itself, and delegates:

```ruby
def run(argv)
  options = parse(argv)
  return 0 if options[:exit_early]

  boot_rails(options[:rails_root])
  report = Generator.new(build_configuration(options)).generate
  @stdout.puts report.summary
  0
rescue StandardError => e
  @stderr.puts "Error: #{e.message}"
  1
end
```

— [`cli.rb:19-30`](../lib/rails_openapi_generator/cli.rb)

The difference from the rake task: the CLI *boots Rails by hand*, because it isn't running inside a Rails process:

```ruby
def boot_rails(rails_root)
  environment = File.join(File.expand_path(rails_root), "config", "environment.rb")
  unless File.exist?(environment)
    raise ConfigurationError,
          "no Rails app found at #{rails_root} (missing config/environment.rb)"
  end

  require environment
end
```

— [`cli.rb:56-64`](../lib/rails_openapi_generator/cli.rb)

`require`ing `config/environment.rb` is exactly what `rake`'s `:environment` task does under the hood — we just do it explicitly.

The whole `run` is wrapped in a `rescue` that prints to stderr and returns exit code 1. A CLI must have a sane exit code: 0 on success, 1 on failure. CI depends on it. We dependency-inject `stdout`/`stderr` so the CLI is testable without capturing the process's real streams — see [`spec/unit/`](../spec/unit/) for the pattern (the CLI is exercised via `interface_parity_spec`).

> **Aside: why three doorways?**
> The rake task is for humans inside a Rails repo. The CLI is for scripts and tools outside it. The programmatic API (`Generator.new(config).document`) is for the *tests* and for users embedding the gem in a larger tool. All three converge on `Generator`. We could have shipped only the rake task, but then the integration tests would have to shell out to rake — slow and awkward. The programmatic API exists first; the other two are thin wrappers. The [interface parity spec](../spec/integration/interface_parity_spec.rb) asserts all three produce the same document.

## Try it yourself

Run all three doorways against the dummy app and confirm they agree.

1. Programmatic (in `irb` from the dummy app root after booting it): `RailsOpenapiGenerator::Generator.new(RailsOpenapiGenerator::Configuration.new).document.keys`.
2. CLI: `bundle exec rails-openapi-generator --rails-root spec/fixtures/dummy --output tmp/cli.json` from the gem root.
3. Read [`spec/integration/interface_parity_spec.rb`](../spec/integration/interface_parity_spec.rb) and find the assertion that ties them together.

Now break it on purpose: set `config.output_path = ""` and call `generate`. Which line raises, and is it before or after any document is built? (Hint: `validate!` runs first in `Generator#generate`.)
