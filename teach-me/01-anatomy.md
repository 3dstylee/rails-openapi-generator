# 1. Anatomy of the repo

A short tour. We'll stand at the top of the tree, name each directory, and say what it's for. By the end you should know which folder to open for any question that arises later.

## The top level

```
.
├── lib/                      # the gem's code
├── exe/                      # the bin shim — runs the CLI
├── spec/                     # tests
├── specs/                    # design docs, one per feature
├── rails-openapi-generator.gemspec
├── Gemfile / Gemfile.lock
├── CHANGELOG.md
├── README.md
└── CLAUDE.md
```

Two things look unusual at first glance: `spec/` and `specs/` are different. `spec/` holds RSpec tests. `specs/` holds *specifications* — design documents written before code, one folder per feature. Chapter 12 unpacks that. For now, file them as "tests" and "design docs."

[`rails-openapi-generator.gemspec`](../rails-openapi-generator.gemspec) tells RubyGems what the gem ships. Notice:

```ruby
spec.files = Dir["lib/**/*", "exe/*", "README.md", "CHANGELOG.md"]
```

We ship `lib/`, `exe/`, and two markdown files. `spec/` is not packaged — tests stay in the repo. `specs/` is not packaged either — design docs are for us, not our users.

We have two runtime dependencies, [`railties`](https://rubygems.org/gems/railties) (we plug into a Rails app, so we need it) and [`yard`](https://rubygems.org/gems/yard) (we parse YARD comments for descriptions). Every other Rails dependency is a development dependency — the gem doesn't drag the whole framework into your bundle.

## Inside `lib/`

```
lib/
├── rails-openapi-generator.rb    # a one-line alias
├── rails_openapi_generator.rb    # the real entry point
├── tasks/
│   └── rails_openapi_generator.rake
└── rails_openapi_generator/
    ├── version.rb
    ├── errors.rb
    ├── configuration.rb
    ├── route.rb / route_collector.rb
    ├── ... 30+ files ...
    └── generator.rb              # the orchestrator
```

Why two top-level files? Ruby gem naming convention says `rails-openapi-generator` (the gem name, with a hyphen) should be `require`-able. But Ruby file names can't contain hyphens cleanly, so the canonical file uses underscores: [`rails_openapi_generator.rb`](../lib/rails_openapi_generator.rb). The hyphenated file [`rails-openapi-generator.rb`](../lib/rails-openapi-generator.rb) just forwards to it — a courtesy to users who guess wrong.

The canonical entry point requires each module in dependency order, then defines `RailsOpenapiGenerator.configure`:

```ruby
require_relative "rails_openapi_generator/version"
require_relative "rails_openapi_generator/errors"
require_relative "rails_openapi_generator/configuration"
# ... 30 more requires ...
require_relative "rails_openapi_generator/generator"
require_relative "rails_openapi_generator/cli"
```

We have no autoloader. Every file is required eagerly. That's intentional: the gem is short-lived (one run, then exit), so paying the load cost upfront beats the complexity of Zeitwerk-style lazy loading. It also makes the load order legible — read top to bottom and you can predict which files depend on which.

> **Aside: why no namespace folder for the entry point?**
> A common Ruby gem layout puts the entry as `lib/rails_openapi_generator.rb` plus everything under `lib/rails_openapi_generator/`. We follow that exactly. The `tasks/` folder breaks the convention only because Rails' rake-task autoloader expects `lib/tasks/`. Chapter 9 returns to this.

## Inside `lib/rails_openapi_generator/`

Thirty-odd files. Let's group them by purpose.

**Plumbing.** [`version.rb`](../lib/rails_openapi_generator/version.rb), [`errors.rb`](../lib/rails_openapi_generator/errors.rb), [`configuration.rb`](../lib/rails_openapi_generator/configuration.rb), [`railtie.rb`](../lib/rails_openapi_generator/railtie.rb), [`cli.rb`](../lib/rails_openapi_generator/cli.rb).

**Routes.** [`route.rb`](../lib/rails_openapi_generator/route.rb) (the data class), [`route_collector.rb`](../lib/rails_openapi_generator/route_collector.rb) (asks Rails for its route set).

**Source location.** [`source_locator.rb`](../lib/rails_openapi_generator/source_locator.rb) — given a route, find the controller's `.rb` file. [`yard_parser.rb`](../lib/rails_openapi_generator/yard_parser.rb) — parse that file with Ripper, capture each action's AST and YARD comment. [`method_resolver.rb`](../lib/rails_openapi_generator/method_resolver.rb) — follow a method call to its definition, anywhere on the controller's ancestor chain.

**Static evaluation.** [`literal_evaluator.rb`](../lib/rails_openapi_generator/literal_evaluator.rb) — turn an AST literal into a Ruby value. [`constant_resolver.rb`](../lib/rails_openapi_generator/constant_resolver.rb) — turn `Order::STATUSES` into its actual array. These two are the heart of "static analysis" — chapter 2.

**Parameter extraction.** [`param_extractor.rb`](../lib/rails_openapi_generator/param_extractor.rb), [`schema_mapper.rb`](../lib/rails_openapi_generator/schema_mapper.rb), [`doc_comment_extractor.rb`](../lib/rails_openapi_generator/doc_comment_extractor.rb), [`implicit_param_scanner.rb`](../lib/rails_openapi_generator/implicit_param_scanner.rb).

**Response inference.** This is the largest cluster — six files. [`render_extractor.rb`](../lib/rails_openapi_generator/render_extractor.rb) finds every `render`, `head`, and `redirect_to` in an action. [`render_classifier.rb`](../lib/rails_openapi_generator/render_classifier.rb) decides whether the action returns JSON, HTML, a file download, or a redirect. [`view_locator.rb`](../lib/rails_openapi_generator/view_locator.rb) finds the action's view file. [`jbuilder_parser.rb`](../lib/rails_openapi_generator/jbuilder_parser.rb) reads a `.json.jbuilder` template into a schema. [`schema_sidecar_loader.rb`](../lib/rails_openapi_generator/schema_sidecar_loader.rb) reads a `.schema.json` override. [`response.rb`](../lib/rails_openapi_generator/response.rb) and [`response_builder.rb`](../lib/rails_openapi_generator/response_builder.rb) assemble the final response set.

**Following the controller chain.** [`controller_method_walker.rb`](../lib/rails_openapi_generator/controller_method_walker.rb), [`helper_binding_walker.rb`](../lib/rails_openapi_generator/helper_binding_walker.rb), [`wrapper_download_resolver.rb`](../lib/rails_openapi_generator/wrapper_download_resolver.rb), [`before_action_resolver.rb`](../lib/rails_openapi_generator/before_action_resolver.rb), [`rescue_from_resolver.rb`](../lib/rails_openapi_generator/rescue_from_resolver.rb). Chapter 8.

**Assembly.** [`operation_builder.rb`](../lib/rails_openapi_generator/operation_builder.rb) builds one operation. [`document_builder.rb`](../lib/rails_openapi_generator/document_builder.rb) assembles them into the OpenAPI document. [`writer.rb`](../lib/rails_openapi_generator/writer.rb) serializes to disk. [`report.rb`](../lib/rails_openapi_generator/report.rb) is the run summary.

**The orchestrator.** [`generator.rb`](../lib/rails_openapi_generator/generator.rb) is the top of the call tree — chapter 5.

That's it. Thirty files, but they fall into seven clean groups. If you find yourself lost in chapter 7, come back to this list.

## `exe/` — the binary

A one-file wrapper that boots the CLI. Open it:

```ruby
#!/usr/bin/env ruby
require "rails_openapi_generator"
exit RailsOpenapiGenerator::CLI.start(ARGV)
```

That's the whole thing. The CLI logic lives in [`lib/rails_openapi_generator/cli.rb`](../lib/rails_openapi_generator/cli.rb) — `exe/rails-openapi-generator` is just the shim RubyGems puts on the user's `$PATH`. Chapter 9 walks the CLI.

## `spec/` — tests

```
spec/
├── spec_helper.rb
├── support/
│   └── dummy_app.rb
├── fixtures/dummy/             # a real Rails app, just for tests
├── unit/                       # one file per class under lib/
└── integration/                # the gem run end-to-end on dummy/
```

The dummy app is a real Rails 7 app: routes, controllers, views, concerns. Tests in `integration/` boot it once per process and run `Generator.new(config).generate` against it. Tests in `unit/` exercise one class in isolation with a small AST fixture. Chapter 11 returns here.

## `specs/` — design docs

Twenty-one numbered folders, each a feature: `001-openapi-rake-generator`, `002-response-bodies`, … `021-literal-examples`. Each folder has `spec.md` (what to build), `plan.md` (how), `research.md` (decisions), `tasks.md` (steps), and `quickstart.md`. Chapter 12 explains why we work this way.

## Try it yourself

Open [`lib/rails_openapi_generator.rb`](../lib/rails_openapi_generator.rb) — the entry point — and read the `require_relative` block top to bottom. Without looking ahead, predict the order the chapters in this book will introduce things. Then check yourself against the TOC in [`00-index.md`](00-index.md). Where did the load order surprise you? (Hint: the load order is roughly leaves-before-roots; the book goes roots-before-leaves. Why might that be?)
