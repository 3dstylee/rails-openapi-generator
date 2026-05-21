# 11. Tests

The test suite has 25 unit files and 27 integration files. That ratio tells you something: this gem is tested as much from the *outside* (run it on a real app, check the output) as from the inside (poke one class with a fake AST). This chapter explains the layers and why each exists.

## The dummy app: a real Rails app as a fixture

The center of the test suite is [`spec/fixtures/dummy/`](../spec/fixtures/dummy/) — a complete, bootable Rails 7 application that exists only to be analyzed.

```
spec/fixtures/dummy/
├── config/
│   ├── application.rb
│   ├── environment.rb
│   └── routes.rb
├── app/
│   ├── controllers/
│   │   ├── application_controller.rb
│   │   ├── api/*.rb            # ~25 controllers
│   │   └── concerns/*.rb
│   ├── views/api/**/*.jbuilder
│   └── services/
```

Why a real app and not stubbed routes? Because the gem's whole job is to read Rails-shaped code. Stubs would test our understanding of Rails, not Rails itself. The dummy app calls `_process_action_callbacks`, has real `rescue_from` chains, real concerns, real view files — every reflective hook the gem uses (chapter 8) is exercised against the genuine Rails implementation.

Each controller in the dummy app is a *fixture for one feature*. `users_controller.rb` is the canonical happy path. `multi_status_controller.rb` exercises the union/dedup rules. `respond_to_controller.rb` exercises format gates. `cyclic` in `reports_controller.rb` exercises the recursion guard. The routes file is the index — read it and you can map each route to the feature it tests.

The app boots once per process:

```ruby
module DummyApp
  ROOT = File.expand_path("../fixtures/dummy", __dir__)

  def boot!
    return if @booted

    require File.join(ROOT, "config", "environment")
    @booted = true
  end
end
```

— [`spec/support/dummy_app.rb:4-14`](../spec/support/dummy_app.rb)

The `return if @booted` guard matters: you can only boot a Rails app once per Ruby process. Integration specs opt in with a tag:

```ruby
config.before(:each, :rails_app) { DummyApp.boot! }
```

— [`spec/spec_helper.rb:20`](../spec/spec_helper.rb)

So a spec marked `:rails_app` gets a booted app; an unmarked unit spec doesn't pay the boot cost.

## Layer 1: unit specs

[`spec/unit/`](../spec/unit/) has one file per class in `lib/`. They construct the input struct (or a small AST via `Ripper.sexp`) and assert on the output struct. No Rails boot, no filesystem (mostly).

The data-model boundaries from chapter 4 are what make this possible. A `RenderExtractor` unit spec feeds it a Ripper AST and checks the `RenderSite`s. An `OperationBuilder` unit spec feeds it a `Route` + `ParamCall`s and checks the `Endpoint`. Each class is tested at its own boundary, in isolation.

These are fast and precise. When one breaks, you know exactly which class regressed.

## Layer 2: integration specs

[`spec/integration/`](../spec/integration/) boots the dummy app and runs the *whole* generator, then asserts on the document. There's roughly one integration file per feature, and the names map to the `specs/` folders: [`feature_020_schema_sidecars_spec.rb`](../spec/integration/feature_020_schema_sidecars_spec.rb), [`multi_status_responses_spec.rb`](../spec/integration/multi_status_responses_spec.rb), [`respond_to_format_blocks_spec.rb`](../spec/integration/respond_to_format_blocks_spec.rb), etc.

A typical integration assertion reaches deep into the document:

```ruby
document.dig("paths", "/api/users/{id}", "get", "responses", "200",
             "content", "application/json", "schema", "properties").keys
```

— [`spec/integration/determinism_spec.rb:25-26`](../spec/integration/determinism_spec.rb)

Integration specs catch the bugs that unit specs can't: wiring errors, the wrong call order in the generator, a feature that works in isolation but interacts badly with another. They're slower but they test what the user actually gets.

## Layer 3: cross-cutting property specs

A few integration specs don't test a feature — they test a *property* that must hold across the whole gem.

**Determinism.** [`determinism_spec.rb`](../spec/integration/determinism_spec.rb) runs `generate` twice and asserts the outputs are `eq`. Then it does the same for individual operations, oneOf lists, parameter orders. This is the enforcement mechanism for the chapter-3 byte-identical promise. Every aggregation point we sort has a test here.

**Resilience.** [`resilience_spec.rb`](../spec/integration/resilience_spec.rb) and [`response_resilience_spec.rb`](../spec/integration/response_resilience_spec.rb) feed the gem broken input (the `api/orphan` route, malformed sidecars) and assert the run *completes* with warnings, never raises. This enforces the chapter-10 `success? == true` policy.

**Schema validity.** [`spec/support/openapi_schema.rb`](../spec/support/openapi_schema.rb) defines a focused JSON Schema describing exactly the OpenAPI structures we emit, and validates generated documents against it with [`json_schemer`](https://rubygems.org/gems/json_schemer):

```ruby
SCHEMA = {
  "$schema" => "https://json-schema.org/draft/2020-12/schema",
  "type" => "object",
  "required" => %w[openapi info paths],
  # ...
}
```

— [`spec/support/openapi_schema.rb:8-12`](../spec/support/openapi_schema.rb)

This is a guard against emitting structurally invalid OpenAPI. We wrote our own focused schema rather than validating against the full OpenAPI meta-schema, because the full meta-schema would accept things we never emit and reject nothing we care about — a narrow schema catches *our* mistakes precisely.

**Interface parity.** [`interface_parity_spec.rb`](../spec/integration/interface_parity_spec.rb) (chapter 9) runs the library API, the rake task, and the CLI, and asserts all three produce the same document. This guards against the three doorways drifting apart.

**Performance.** [`performance_spec.rb`](../spec/integration/performance_spec.rb) asserts a run stays under a time budget — the cache-regression guard from chapter 10.

## The test-as-spec correspondence

Notice the integration files named `feature_NNN_*`. They correspond one-to-one with the `specs/NNN-*/` design folders (chapter 12). When a feature is designed, its acceptance criteria become an integration spec. The test file is the executable form of the spec document.

This is why the suite reads like a feature log: `feature_001_regression_spec.rb` guards the original behavior, `feature_017_implicit_200_spec.rb` guards feature 17's addition, and so on. A new feature adds a new spec file and may extend the determinism / resilience specs, but rarely touches old feature specs — they're regression anchors.

> **Aside: testing AST code is its own skill.**
> The unit specs for AST-heavy classes (`render_extractor`, `param_extractor`, `jbuilder_parser`) build their input with `Ripper.sexp("...ruby source...")`. This means the *test* contains a snippet of Ruby-as-string, and the assertion checks what we extracted from it. It reads a little oddly at first — code about code — but it's the most direct way to test a parser: give it source, check the structured output. When you add an AST feature, the test snippet *is* the spec for what syntax you support.

## Running the suite

```sh
bundle exec rspec                    # everything
bundle exec rspec spec/unit          # fast, no Rails boot
bundle exec rspec spec/integration   # boots the dummy app
bundle exec rubocop                  # style
```

`spec_helper.rb` randomizes order (`config.order = :random`) and resets the configuration singleton before each example:

```ruby
config.before do
  RailsOpenapiGenerator.reset_configuration!
end
```

— [`spec/spec_helper.rb:15-17`](../spec/spec_helper.rb)

The reset matters because `Configuration` is a process-wide singleton (chapter 9). Without the reset, a spec that sets `config.title = "X"` would leak into the next spec. Random order means any such leak surfaces as a flaky failure — which is exactly when you want to find it.

## Try it yourself

Pick a feature you found interesting in earlier chapters — say, helper argument propagation (chapter 8). Open [`spec/integration/feature_018_helper_arg_propagation_spec.rb`](../spec/integration/feature_018_helper_arg_propagation_spec.rb) and the controller it exercises, [`spec/fixtures/dummy/app/controllers/api/binding_helpers_controller.rb`](../spec/fixtures/dummy/app/controllers/api/binding_helpers_controller.rb). Read them side by side. The controller is the *input*; the spec is the *expected output*.

Now add a new action to that controller that calls a helper with a literal you'd expect to be propagated. Write the integration assertion you'd expect to pass. Run it. Did the gem propagate the literal? If not, walk back through chapter 8 to find where it stopped.
