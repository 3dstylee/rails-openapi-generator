# 4. The data model

Almost every class in this gem is either a *data class* (a `Struct` carrying values) or an *active class* (one with behavior that produces or consumes those values). This chapter names the data classes. The rest of the book references them constantly.

We use `Struct.new(..., keyword_init: true)` rather than `Class.new` for one reason: equality and inspection come for free, which makes test diffs readable. `keyword_init: true` makes constructors self-documenting at call sites — `Route.new(http_method: "GET", path: "/users", …)` is harder to get wrong than positional args.

## `Route`

The unit of work. One per HTTP method × path pair.

```ruby
class Route
  attr_reader :http_method, :path, :controller, :action, :path_params

  def initialize(http_method:, path:, controller:, action:, external: false)
    @http_method = http_method.to_s.upcase
    @path        = path
    @controller  = controller
    @action      = action
    @external    = external
    @path_params = path.scan(/[:*]([A-Za-z_][A-Za-z0-9_]*)/).flatten
  end
```

— [`route.rb:5-15`](../lib/rails_openapi_generator/route.rb)

`Route` is the only data class we wrote as a real `class`, not a `Struct`, because it has light derived state (`path_params`, `controller_class_name`) and a couple of predicates. It's still a value type — once built, you don't mutate it.

`external?` marks redirects and mounted engines: routes with no controller action to inspect. We skip those routes (with a `report.skip`) rather than fail.

## `ActionSource`

The output of parsing one action method.

```ruby
ActionSource = Struct.new(:name, :docstring, :method_node, :line, keyword_init: true)
```

— [`yard_parser.rb:9`](../lib/rails_openapi_generator/yard_parser.rb)

Four fields: the action name, the YARD docstring text, the Ripper AST node for the `def`, and the source line number. From this everything downstream reads either text (`docstring`) or AST (`method_node`).

## `ParamCall`

One `param!` declaration, statically resolved.

```ruby
ParamCall = Struct.new(
  :name, :type, :required, :constraints, :fully_resolved, :nested,
  keyword_init: true
) do
  def fully_resolved?
    fully_resolved
  end
end
```

— [`param_extractor.rb:9-16`](../lib/rails_openapi_generator/param_extractor.rb)

`name` and `type` are strings. `required` is a Boolean. `constraints` is a Hash like `{ in: 1..100, blank: false }`. `nested` carries the tree of child `ParamCall`s for `Hash`/`Array` declarations with a block — `nil` for flat calls. `fully_resolved` is the gateway to the report: a ParamCall with an unresolved argument becomes a warning.

## `RenderSite` and `RenderResult`

The two structs at the heart of response inference. The first describes one render call somewhere in reachable code:

```ruby
RenderSite = Struct.new(
  :explicit_status, :schema, :head, :source,
  :template_name, :format_hint, :kind_hint, :content_type,
  keyword_init: true
)
```

— [`render_extractor.rb:26-30`](../lib/rails_openapi_generator/render_extractor.rb)

That's eight fields because a render site is more than just "render X." We need to know its status, the schema we recovered (if any), whether it's a `head` (body-less), where the site came from (the action body? a helper? a `before_action`?), the template name for an unresolved `render :foo`, and a few more annotations the resolver fills in. The big docstring above the struct is worth reading in full.

The second describes one *action's* output as a whole:

```ruby
RenderResult = Struct.new(
  :schema, :renders_json, :explicit_status, :head, :file_download, :html_inline, :template,
  :redirect_status, :render_sites,
  keyword_init: true
)
```

— [`render_extractor.rb:53-57`](../lib/rails_openapi_generator/render_extractor.rb)

An action's `RenderResult` aggregates all its `RenderSite`s plus high-level flags: "does this action render JSON? does it `head`? does it `send_file`?"

The two structs split responsibilities cleanly: `RenderExtractor` produces them, `RenderClassifier` consumes the flags to pick a kind, `ResponseBuilder` consumes the sites to build the per-status response set.

## `Classification`

The output of [`RenderClassifier`](../lib/rails_openapi_generator/render_classifier.rb):

```ruby
Classification = Struct.new(:kind, :render_result, :jbuilder_file, :template_name, keyword_init: true)
```

— [`render_classifier.rb:10`](../lib/rails_openapi_generator/render_classifier.rb)

`kind` is `:json`, `:html_page`, `:file_download`, `:redirect`, or `:undeterminable`. The classifier passes the `RenderResult` through and adds the resolved view file when relevant.

## `Response` and `ResponseEntry`

The output of [`ResponseBuilder`](../lib/rails_openapi_generator/response_builder.rb).

```ruby
ResponseEntry = Struct.new(:status, :body, :content_types, keyword_init: true)

Response = Struct.new(
  :entries, :description, :undeterminable, :kind, :page_reference,
  keyword_init: true
) do
  # ...
end
```

— [`response.rb:13, 28-32`](../lib/rails_openapi_generator/response.rb)

One `ResponseEntry` per status code. A `Response` is a list of entries plus operation-wide metadata: the description string, the `kind` (so `DocumentBuilder` knows whether to emit `application/json` or `text/html`), and `undeterminable` (so the report can warn).

The `entries`-shadows-`Struct#entries`-alias note in the source is worth reading; we accept the shadowing because the rename would be worse.

## `Endpoint` and `Parameter`

The output of [`OperationBuilder`](../lib/rails_openapi_generator/operation_builder.rb), and the input to [`DocumentBuilder`](../lib/rails_openapi_generator/document_builder.rb).

```ruby
Parameter = Struct.new(:name, :location, :required, :schema, :description, keyword_init: true)

Endpoint = Struct.new(
  :http_method, :path, :summary, :description, :parameters, :request_body, :operation_id, :tag,
  :response,
  keyword_init: true
)
```

— [`operation_builder.rb:5-12`](../lib/rails_openapi_generator/operation_builder.rb)

By the time you hold an `Endpoint`, it carries everything the document needs about one operation. The `DocumentBuilder` is then a pure mapping from a list of `Endpoint`s to a Hash — no fetching, no resolution.

## `GenerationReport`

Not a struct — it's a small class with mutable counters. Why? Because we increment counters during the pipeline, and a `Struct` with `keyword_init: true` would be awkward for that. See [`report.rb`](../lib/rails_openapi_generator/report.rb):

```ruby
class GenerationReport
  attr_accessor :processed_count, :output_path, :html_page_count, :file_download_count
  attr_reader :skipped, :warnings

  def initialize
    @processed_count     = 0
    @html_page_count     = 0
    @file_download_count = 0
    @skipped             = []
    @warnings            = []
    @output_path         = nil
  end
```

— [`report.rb:5-16`](../lib/rails_openapi_generator/report.rb)

The report is threaded through every stage. Any code that wants to record a non-fatal problem calls `report.warn(msg)` or `report.skip(route, reason)`.

## The shape of one run

Putting them together — one route is processed by passing data forward through these types:

```
Route
  → ActionSource           (YardParser.parse → method node + docstring)
    → [ParamCall]          (ParamExtractor.extract)
    → RenderResult         (RenderExtractor.extract)
       → Classification    (RenderClassifier.classify)
       → Response          (ResponseBuilder.build)
    → Endpoint             (OperationBuilder.build)
```

Then `[Endpoint]` → `Document` via `DocumentBuilder.build`. That's the whole flow. Chapter 5 walks the orchestration that drives it.

## Why so many tiny structs

A common refactor temptation is to merge structs. Why is `ResponseEntry` separate from `RenderSite`? Why does `Endpoint` carry a `Response` rather than inlining its fields?

Two reasons, both load-bearing:

1. **Locality of change.** Adding a field to `RenderSite` (which we did in [feature 011](../specs/011-template-renders-in-helpers/) for template name) doesn't ripple into `Endpoint`. The structs are deliberately decoupled by transform.
2. **Testability.** Each transform (`extract`, `classify`, `build`) takes the previous struct and returns the next. Unit specs can construct fake instances of any intermediate type without booting the rest of the pipeline.

The cost: more names to learn. The book makes that easier by introducing them once, here.

## Try it yourself

Open [`spec/unit/operation_builder_spec.rb`](../spec/unit/operation_builder_spec.rb). Find a test that constructs a `Route`, a `ParamCall`, and a `Response` by hand and calls `OperationBuilder#build`. Notice that the test never touches a Ripper AST. That's the payoff for the struct boundaries. Now go to [`spec/unit/render_extractor_spec.rb`](../spec/unit/render_extractor_spec.rb) and notice the opposite — that one *only* uses ASTs, because that's the input to `RenderExtractor`. The data model lets each test be small.

Pick one struct (`ParamCall` is a good choice). Without reading ahead, sketch the OpenAPI parameter object you'd build from it. Then check yourself against [`operation_builder.rb:102-106`](../lib/rails_openapi_generator/operation_builder.rb).
