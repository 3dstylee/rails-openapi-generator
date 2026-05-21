# 5. The pipeline

[`Generator`](../lib/rails_openapi_generator/generator.rb) is the only file in `lib/` that orchestrates. Everything else does one job. This chapter reads `generator.rb` top to bottom — slowly. It's the central nervous system.

## The public surface

Two public methods:

```ruby
def generate
  @configuration.validate!
  document = build_document
  @report.output_path = Writer.new(@configuration).write(document)
  @report
end

def document
  @configuration.validate!
  build_document
end
```

— [`generator.rb:11-22`](../lib/rails_openapi_generator/generator.rb)

`generate` writes to disk and returns the report. `document` returns the in-memory hash without writing. Two surfaces, one core. We did this because the integration tests want the hash (so they can assert on it without re-reading from disk), but the CLI and rake task want the file written.

Both call `validate!` first. Configuration errors raise before any work happens.

## The build sequence

```ruby
def build_document
  @report = GenerationReport.new
  setup_pipeline
  endpoints = routes_to_process.filter_map { |route| build_endpoint(route) }
  DocumentBuilder.new(@configuration).build(endpoints)
end
```

— [`generator.rb:26-31`](../lib/rails_openapi_generator/generator.rb)

Four lines. Read them carefully — they are the program:

1. Fresh report. The report mutates during the run; a stale one across runs would conflate counts.
2. `setup_pipeline` wires up every collaborator. We'll come back to this.
3. For every route, build an endpoint. `filter_map` because some routes return `nil` (skipped — see `routes_to_process`).
4. Hand the endpoints to the `DocumentBuilder`.

That's the whole program. Everything else is the body of `build_endpoint`.

## `setup_pipeline` — the dependency graph

```ruby
def setup_pipeline
  views_root = views_root_path
  LiteralEvaluator.resolver = ConstantResolver.new
  @locator          = SourceLocator.new
  @parser           = YardParser.new
  @param_extractor  = ParamExtractor.new
  @doc_extractor    = DocCommentExtractor.new
  @render_extractor = RenderExtractor.new
  @view_locator     = ViewLocator.new(views_root: views_root)
  @sidecar_loader   = SchemaSidecarLoader.new(report: @report)
  @jbuilder_parser  = JbuilderParser.new(views_root: views_root, sidecar_loader: @sidecar_loader)
  @views_root       = views_root
  @method_resolver  = MethodResolver.new(yard_parser: @parser)
  @walker           = ControllerMethodWalker.new(
    method_resolver: @method_resolver, max_depth: @configuration.method_resolution_depth
  )
  @helper_binding_walker = HelperBindingWalker.new(
    method_resolver: @method_resolver, max_depth: @configuration.method_resolution_depth
  )
  @wrapper_resolver = WrapperDownloadResolver.new(walker: @walker)
  @implicit_scanner = ImplicitParamScanner.new(walker: @walker)
  @before_action_resolver = BeforeActionResolver.new(method_resolver: @method_resolver)
  @rescue_from_resolver   = RescueFromResolver.new(method_resolver: @method_resolver)
  @classifier       = RenderClassifier.new(view_locator: @view_locator, wrapper_resolver: @wrapper_resolver)
  @response_builder = ResponseBuilder.new
  @operation_builder = OperationBuilder.new
end
```

— [`generator.rb:33-59`](../lib/rails_openapi_generator/generator.rb)

It is a lot. Let's not skim. Two patterns to notice:

**One instance per collaborator, one collaborator per concern.** We do not pass classes around — we instantiate and inject. The `MethodResolver`, for example, is shared by *seven* downstream collaborators. Sharing the instance shares its parse cache, which matters: parsing a controller file is the most expensive thing this gem does.

**The `LiteralEvaluator.resolver =` line is unusual.** `LiteralEvaluator` is a module, not a class. We give it module-level state for the duration of one run: a fresh `ConstantResolver` whose cache lives only this long. We decided this trade after some thought — pure functional purity would mean passing the resolver into every `LiteralEvaluator.evaluate(...)` call, threading it through `ParamExtractor`, `RenderExtractor`, and `JbuilderParser`. The module-level write keeps callers simple at the cost of being non-reentrant. We are not reentrant.

> **Aside: why not Dependency Injection container?**
> Because Ruby has constructors that take keyword args. A DI container solves a problem that doesn't exist at our scale. Twenty lines of explicit wiring beats five lines of magical wiring you can't follow with a debugger.

## `routes_to_process`

```ruby
def routes_to_process
  RouteCollector.new(route_filter: @configuration.route_filter).collect.filter_map do |route|
    if route.resolvable?
      route
    else
      @report.skip(route, "no backing controller action")
      nil
    end
  end
end
```

— [`generator.rb:61-70`](../lib/rails_openapi_generator/generator.rb)

[`RouteCollector`](../lib/rails_openapi_generator/route_collector.rb) talks to `Rails.application.routes`. The redirect routes and mounted-engine routes don't have a controller action, so `route.resolvable?` returns false — we record them on the report and skip.

## `build_endpoint` — the per-route pipeline

This is where one route becomes one endpoint:

```ruby
def build_endpoint(route)
  file = locate_source(route)
  if @configuration.source_excluded?(file)
    @report.skip(route, "controller source excluded by exclude_source_paths")
    return nil
  end

  action_source    = file && @parser.parse(file)[route.action]
  action_node      = action_source&.method_node
  controller_class = @locator.controller_class(route)
  param_calls      = @param_extractor.extract(action_source)
  warn_unresolved(route, param_calls)

  response = build_response(route, action_source, controller_class)
  count_kind(response)
  endpoint = @operation_builder.build(
    route,
    doc_comment: @doc_extractor.extract(action_source),
    param_calls: param_calls,
    source_location: source_location_for(file, action_source),
    response: response,
    implicit_params: @implicit_scanner.scan(controller_class, action_node)
  )
  @report.processed_count += 1
  endpoint
rescue StandardError => e
  @report.warn("#{route.http_method} #{route.path}: #{e.message}")
  @report.processed_count += 1
  @operation_builder.build(route)
end
```

— [`generator.rb:72-101`](../lib/rails_openapi_generator/generator.rb)

Read the names alone and you see the data model from chapter 4: locate `file`, parse `action_source`, extract `param_calls`, build `response`, build `endpoint`. The struct names from chapter 4 line up one-to-one.

Two things to call out:

**The rescue clause.** Anywhere down the call tree, an unexpected error in one route becomes a *warning* and a minimal `OperationBuilder.build(route)` — an endpoint with just the route info, no params, no response body. This is the "warn, never raise" policy from chapter 2 made concrete at the top of the pipeline. A user with one broken controller still gets a complete document for the other 99.

**The order matters.** `action_source` is extracted before `controller_class` because we want `action_source` even when the controller class can't be loaded. (Rails autoloading can fail in some odd dummy-app setups.) `param_calls` is extracted before `build_response` because the response builder doesn't need them.

## `build_response` — the deepest call

```ruby
def build_response(route, action_source, controller_class)
  render_result = @render_extractor.extract(action_source)
  resolve_template_sites!(render_result.render_sites, route)
  classification = @classifier.classify(
    route, render_result,
    controller_class: controller_class,
    action_node: action_source&.method_node
  )
  view_schema    = classification.jbuilder_file ? @jbuilder_parser.parse(classification.jbuilder_file) : nil
  extra_sites    = collect_extra_sites(route, controller_class, action_source)
  resolve_template_sites!(extra_sites, route)
  response = @response_builder.build(
    route, classification: classification, view_schema: view_schema, extra_sites: extra_sites
  )

  apply_action_sidecar!(response, route)

  if response.undeterminable?
    @report.warn("#{route.http_method} #{route.path}: response shape could not be determined")
  end
  response
end
```

— [`generator.rb:103-124`](../lib/rails_openapi_generator/generator.rb)

Six stages. They're worth naming, because chapter 7 takes them one at a time:

1. **Extract.** Look at the action body itself; find every `render` / `head` / `redirect_to`.
2. **Resolve.** For each render that just names a template (`render :foo`), find the view file.
3. **Classify.** JSON, HTML page, file download, redirect, or undeterminable?
4. **Parse the view.** If JSON, recover the schema from `.json.jbuilder`.
5. **Collect extras.** Find every render reachable through helpers, `before_action`s, and `rescue_from` handlers.
6. **Build.** Hand it all to `ResponseBuilder`, which groups by status, unions schemas, and emits one `Response`.

Then we apply the action-level sidecar override and warn if we couldn't determine anything.

## A worth-quoting moment: `apply_action_sidecar!`

Most of `generator.rb` reads naturally — there's a lot of it but each line is straightforward. One method is more interesting. The schema-sidecar feature lets a user drop a `show.schema.json` next to their controller's view path to override our inference. The generator applies it like this:

```ruby
def apply_action_sidecar!(response, route)
  return unless response.kind == :json

  schema = @sidecar_loader.for_view(@views_root, route.controller, route.action)
  return if schema.nil?

  convention = ResponseBuilder::STATUS_BY_METHOD.fetch(route.http_method, ResponseBuilder::DEFAULT_STATUS)
  entry = response.entries.find { |e| e.status == convention }
  if entry.nil?
    response.entries << ResponseEntry.new(status: convention, body: schema)
    response.entries.sort_by!(&:status)
  else
    entry.body = schema
    entry.content_types = nil
  end
  response.undeterminable = false
end
```

— [`generator.rb:132-148`](../lib/rails_openapi_generator/generator.rb)

The work itself is mundane. The comment above it — read it in source — is the reason this lives in the orchestrator and not the response builder. The sidecar override is a *cross-cutting concern* between inference and convention: it overrides our inferred body, *and* it un-marks the response undeterminable, *and* it only applies to JSON kinds. Each of those rules belongs to a different layer. Pulling it together in `Generator` keeps each layer simple.

## What `Generator` is *not* responsible for

- Parsing source. (That's `YardParser` + `Ripper`.)
- Classifying render kinds. (That's `RenderClassifier`.)
- Building the document. (That's `DocumentBuilder`.)

`Generator` is responsible only for: instantiating collaborators, deciding the call order, threading the report through, and degrading gracefully on errors. The temptation to push logic up here ("just one more conditional") is real and has to be resisted — chapter 7 has a half-page conversation about exactly that for the sidecar code above.

## Try it yourself

Add a `puts route.path` to the top of `build_endpoint`. Run `bundle exec rspec spec/integration/generate_all_endpoints_spec.rb`. Watch the routes scroll by in the order the pipeline visits them. Now grep the run for one path you saw — say `/api/users`. Does the order look like alphabetical? HTTP-method order? Filesystem order? Why? (Hint: chapter 3.)

Revert the `puts` when you're done.
