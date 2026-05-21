# 7. Response bodies

This is the hardest chapter. The response side of the gem has more files, more code, and more decisions than every other side put together. Take your time.

A Rails action can return its body through *at least* four mechanisms: a literal `render json:`, a `.json.jbuilder` template, a partial rendered into a parent template, or a JSON Schema sidecar override. And every action can also `head`, `redirect_to`, `send_file`, render HTML, or `respond_to do |fmt|`. We need to recover all of these statically.

The architecture splits into five pieces:

| File | Job |
|---|---|
| [`render_extractor.rb`](../lib/rails_openapi_generator/render_extractor.rb) | Find every `render`/`head`/`redirect`/`send_file` call. |
| [`view_locator.rb`](../lib/rails_openapi_generator/view_locator.rb) | Find the action's view file on disk. |
| [`render_classifier.rb`](../lib/rails_openapi_generator/render_classifier.rb) | Decide: JSON, HTML page, file download, redirect, or unknown? |
| [`jbuilder_parser.rb`](../lib/rails_openapi_generator/jbuilder_parser.rb) | Parse a `.json.jbuilder` template into a schema. |
| [`response_builder.rb`](../lib/rails_openapi_generator/response_builder.rb) | Group sites by status, union schemas, emit a `Response`. |

Plus [`schema_sidecar_loader.rb`](../lib/rails_openapi_generator/schema_sidecar_loader.rb) for the override path.

## Step 1: extract every render site

[`RenderExtractor#extract`](../lib/rails_openapi_generator/render_extractor.rb) is the entry point. It walks an action's AST and produces a `RenderResult` carrying every `render`, `head`, and `redirect_to` it finds. The interesting part is what counts as a "site":

```ruby
def render_sites(node, renders, source:)
  json_sites = renders.filter_map { |render| json_site(render, source) }
  template_sites = renders.filter_map { |render| template_site(render, source) }
  head_sites = head_sites(node, source)
  gate_sites = respond_to_gate_sites(node, source)
  json_sites + template_sites + head_sites + gate_sites
end
```

— [`render_extractor.rb:143-149`](../lib/rails_openapi_generator/render_extractor.rb)

Four kinds of site, all merged into one list:

- `json_site` — `render json: { ... }` calls.
- `template_site` — `render :foo` or `render "users/show"` — an unresolved template reference.
- `head_sites` — `head :no_content`, `head 200`.
- `gate_sites` — the format gates inside `respond_to do |fmt| ... end`.

The `respond_to` handling is the strangest. Rails lets you write:

```ruby
respond_to do |format|
  format.json { render json: { ok: true } }
  format.html
end
```

That's *two* sites at one status — one JSON, one HTML — under one operation. We needed a way to thread the content-type per gate down into the site, so we added a `content_type` field on `RenderSite`. Inside `append_gate_sites`:

```ruby
nested.each { |site| site.content_type = gate[:content_type] }
```

— [`render_extractor.rb:340`](../lib/rails_openapi_generator/render_extractor.rb)

The gate's `format.json` tags every contained render-site with `"application/json"`; `format.html` tags them with `"text/html"`. Downstream, the response builder uses those tags to emit a multi-content-type `Response`.

## Step 2: resolve template sites

A `render :foo` doesn't tell us the view file. We have to look up `<controller>/<foo>.json.jbuilder` (or `.html.erb`, etc.). That's [`ViewLocator`](../lib/rails_openapi_generator/view_locator.rb)'s job — but the *Generator* runs the resolution as a post-pass on render-sites:

```ruby
def resolve_template_sites!(sites, route)
  Array(sites).each do |site|
    next unless site&.template?

    if site.template_name == RenderExtractor::SENTINEL_DEFAULT_VIEW
      site.template_name = "#{route.controller}/#{route.action}"
    end

    view = @view_locator.locate_view(route, site.template_name, format_hint: site.format_hint)
    case view&.kind
    when :json
      site.schema = @jbuilder_parser.parse(view.path)
    when :html
      site.kind_hint = :html_page
    end
    site.template_name = nil
    site.format_hint = nil
  end
end
```

— [`generator.rb:155-176`](../lib/rails_openapi_generator/generator.rb)

The `SENTINEL_DEFAULT_VIEW` constant is one of the gem's mild hacks. A `respond_to do |f| f.json; end` (no body block) means "render the action's default view if a JSON request." There's no template name in the source. So the extractor emits a sentinel string; the generator swaps it for `<controller>/<action>` before lookup. The alternative — threading the route through the extractor — would have crossed a layer boundary. We chose the sentinel.

## Step 3: classify

[`RenderClassifier#classify`](../lib/rails_openapi_generator/render_classifier.rb) decides the operation's kind from the render result. Precedence is explicit and ordered:

```ruby
def classify(route, render_result, controller_class: nil, action_node: nil)
  # Precedence: JSON render > send_file > render html: > view lookup.
  return classification(:json, render_result) if render_result.renders_json
  return classification(:file_download, render_result) if render_result.file_download
  return classification(:html_page, render_result) if render_result.html_inline

  classify_by_view(route, render_result, controller_class, action_node)
end
```

— [`render_classifier.rb:26-33`](../lib/rails_openapi_generator/render_classifier.rb)

The comment above is the spec. We made these decisions deliberately:

- A `render json:` anywhere wins, because it's a strong, explicit signal.
- A `send_file` beats inline HTML, because file downloads are usually the punch line of an action ("if all checks pass, *then* send the file").
- A `render html:` beats a view lookup, because the inline call is the more specific signal.
- Otherwise look for a view.

If no view is found, we fall through to two more options: wrapper-resolved download (chapter 8) and redirect. Only if all of those fail do we mark the response `:undeterminable`.

## Step 4: parse the jbuilder

[`JbuilderParser`](../lib/rails_openapi_generator/jbuilder_parser.rb) is its own small parser, separate from the controller one. It produces an OpenAPI schema by walking the AST of a `.json.jbuilder` file.

Jbuilder templates look like Ruby — and they are — but they use a tiny embedded DSL:

```ruby
# app/views/api/users/_user.json.jbuilder
json.extract! user, :id, :name, :email
json.role "member"
json.profile do
  json.bio user.bio
end
```

That's three property kinds in five lines: `extract!` adds permissive properties; `json.role "member"` adds a typed literal; `json.profile do ... end` adds a nested object.

`JbuilderParser#build_schema` walks the statement list:

```ruby
def build_schema(stmts, seen)
  properties  = {}
  array_items = nil
  is_array    = false

  each_json_call(stmts) do |call|
    case call[:method]
    when "array!"
      is_array = true
      array_items = array_items_schema(call, seen)
    when "partial!" then merge_partial(properties, call, seen)
    when "extract!" then extract_properties(properties, call)
    when "set!"     then set_property(properties, call, seen)
    else
      add_property(properties, call, seen) unless IGNORED.include?(call[:method])
    end
  end

  is_array ? { "type" => "array", "items" => array_items || permissive_object } : object_schema(properties)
end
```

— [`jbuilder_parser.rb:51-70`](../lib/rails_openapi_generator/jbuilder_parser.rb)

The IGNORED list — `merge!`, `key_format!`, `cache!`, `nil!` — are jbuilder methods that don't contribute to the schema. We skip them silently.

The same `each_json_call` helper also descends into `if/elsif/else`, `unless`, and `case/when` branches. Branches are *unioned* — every branch's properties end up in the schema. We picked union because the alternative ("emit a `oneOf` of every conditional branch") would explode the schema in pathological templates. Union is permissive but readable.

> **Aside: why parse jbuilder ourselves?**
> jbuilder is just a Rails gem with a Ruby DSL. We could `require` it and `eval` the template, building the JSON tree at "test time" and then inferring its schema. But — chapter 2 — we don't execute code. We also can't reliably stub the `user` local variable. So we use Ripper to read the template's AST and emit a schema that matches the *shape* without the data.

## Step 5: build the response

[`ResponseBuilder#build`](../lib/rails_openapi_generator/response_builder.rb) takes the classification, the view schema, and any extra sites, and assembles a `Response`. The fork at the top dispatches by kind:

```ruby
case classification.kind
when :html_page
  Response.new(status: status_for(route, render_result), kind: :html_page,
               page_reference: classification.template_name)
when :file_download
  Response.new(status: status_for(route, render_result), kind: :file_download)
when :redirect
  Response.new(status: render_result.redirect_status, kind: :redirect)
when :json
  json_response(route, render_result, view_schema, extra_sites)
else
  undeterminable_response(route, render_result, extra_sites)
end
```

— [`response_builder.rb:29-42`](../lib/rails_openapi_generator/response_builder.rb)

Most kinds emit a single-entry `Response`. JSON is the interesting one — it can have multiple entries (one per status) and per-entry unions.

### The union/dedup rules

When the same status has multiple render sites (because the action has `if-else`, or a helper renders one shape and a `rescue_from` renders another), we union them:

```ruby
def union_body(group)
  schemas = group.reject(&:head?).map(&:schema)
  known = schemas.compact
  unique = known.uniq
  case unique.size
  when 0 then nil
  when 1 then unique.first
  else
    { "oneOf" => unique.sort_by { |schema| JSON.generate(schema) } }
  end
end
```

— [`response_builder.rb:199-209`](../lib/rails_openapi_generator/response_builder.rb)

Four cases:

- Zero known schemas → `nil` body. (Body-less entry: a `head`, or all sites unresolved.)
- One unique schema → that schema. (Common case.)
- Multiple distinct schemas → `oneOf`, sorted deterministically.

The sort key — canonical JSON — is the chapter-3 "byte-identical" promise made local: two sites can be present in any order, but the emitted `oneOf` is the same.

### `integrate_view_schema`

The trickiest method in `ResponseBuilder` deals with a real-world case: an action has no inline `render json:`, only a `.json.jbuilder` view, *but* it also has a `rescue_from` that adds a 404 render site. The naive flow would build a `Response` with only the 404 entry (since the action body's "site" is the implicit view, and that's not in the render-sites list). We have to inject the view's schema at the success status:

```ruby
def integrate_view_schema(entries, sites, view_schema, route)
  return if view_schema.nil?

  convention = STATUS_BY_METHOD.fetch(route.http_method, DEFAULT_STATUS)
  action_renders = sites.select { |site| site.source == :action && !site.head? }
  return if action_renders.any? { |site| resolved_status(site, route) == convention && !site.schema.nil? }

  entry = entries.find { |e| e.status == convention }
  if entry.nil?
    entries << ResponseEntry.new(status: convention, body: view_schema)
    entries.sort_by!(&:status)
  elsif entry.body.nil? && entry.content_types.nil?
    entry.body = view_schema
  end
end
```

— [`response_builder.rb:85-99`](../lib/rails_openapi_generator/response_builder.rb)

The early `return` is the careful bit. *If the action body already provided a literal body at the convention status*, don't clobber it — the inline render is more specific than the view. Otherwise, inject or upgrade the entry. This is the kind of code that looks innocuous and is born from a bug report. The comment above it in source records the lineage.

## Schema sidecars

The override hatch. A user can drop a `show.schema.json` next to a controller's view path, and we use it verbatim instead of inferring. [`SchemaSidecarLoader#for_view`](../lib/rails_openapi_generator/schema_sidecar_loader.rb) does the file lookup; the generator applies it as the final step (chapter 5 quoted `apply_action_sidecar!`).

Sidecars exist because inference fails sometimes. A user with rich response types may want to write the schema by hand. We accept that and override the inferred body without judgement.

A malformed sidecar — invalid JSON — emits a warning and falls through to inference. Chapter 10 covers this resilience pattern.

## Why so much code

It's worth a moment to step back. The README description of responses is a paragraph; the implementation is six files and ~1000 lines. Why?

Because Rails is not opinionated about how an action returns data. There is no schema, no type. We have to handle:

- Direct `render json:` (data class)
- Direct `render template:` / `render :foo` (template lookup)
- Implicit `<controller>/<action>` view (no `render` call at all)
- `head` (no body)
- `redirect_to` (no body, status set)
- `send_file` / `send_data` (file download)
- `respond_to do |fmt|` (multi-content-type)
- All of the above in helpers / `before_action` / `rescue_from`
- All of the above with explicit `status:` options
- All of the above as conditional branches

That's the combinatorial explosion. Each file in the response cluster handles one axis cleanly. The result is more files, but each file is small and clearly scoped.

## Try it yourself

Open a fresh Rails console against the dummy app:

```sh
cd spec/fixtures/dummy && bundle exec rails console
```

Then in IRB:

```ruby
$LOAD_PATH.unshift("../../../lib")
require "rails_openapi_generator"

parser = RailsOpenapiGenerator::JbuilderParser.new(views_root: "app/views")
schema = parser.parse("app/views/api/users/_user.json.jbuilder")
puts JSON.pretty_generate(schema)
```

You'll see the schema for `_user.json.jbuilder`. Now edit the template to add a conditional:

```ruby
json.extract! user, :id, :name, :email
json.role "member"
if user.admin?
  json.admin_only true
else
  json.member_only true
end
```

Re-parse. Note the schema has both `admin_only` and `member_only` — the union from `each_json_call`'s conditional handling. (Revert the dummy app changes when you're done.)
