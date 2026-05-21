# 6. Parameters from `param!`

The parameter path is the gentler half of the gem. Compared to response inference, it's a short, clear pipeline: find the `param!` calls, read each one's arguments, translate the type and constraints into an OpenAPI parameter or request-body property.

We'll walk it in three pieces: extraction (`ParamExtractor`), mapping (`SchemaMapper`), and the implicit-params scanner.

## What the user writes

The DSL is from the [`rails_param`](https://rubygems.org/gems/rails_param) gem:

```ruby
def create
  param! :name,  String, required: true, description: "Display name"
  param! :email, String, required: true, format: /.+@.+/
  param! :role,  String, in: %w[admin member]
end
```

Each `param!` declares one request parameter at runtime — `rails_param` checks the actual request matches. We don't care about the runtime check. We care that the source code names every parameter, its type, and a small set of constraints. Each call is a structured fact, sitting in plain Ruby.

## `ParamExtractor`

The extractor walks the action's AST for top-level `param!` calls. There are three syntactic shapes — Ruby allows all of them — and we match each:

```ruby
def param_bang_match(node)
  case node[0]
  when :command
    args = args_list(node[2]) if ident?(node[1], "param!")
    args && { args: args, block: nil }
  when :method_add_arg
    inner = node[1]
    return nil unless inner.is_a?(Array) && inner[0] == :fcall && ident?(inner[1], "param!")

    paren = node[2]
    args = paren.is_a?(Array) && paren[0] == :arg_paren ? args_list(paren[1]) : nil
    args && { args: args, block: nil }
  when :method_add_block
    inner_args = param_bang_match(node[1])
    return nil unless inner_args

    { args: inner_args[:args], block: node[2] }
  end
end
```

— [`param_extractor.rb:70-88`](../lib/rails_openapi_generator/param_extractor.rb)

`:command` is `param! :name, Type` (no parens). `:method_add_arg` is `param!(:name, Type)` (parens). `:method_add_block` wraps either of those with a `do ... end` or `{ ... }` block — for nested `param!` blocks.

We chose to recognize all three because all three appear in real Rails code. A user shouldn't have to format their `param!` calls our way.

## `build_call`: from AST args to `ParamCall`

```ruby
def build_call(found, depth:)
  args = found[:args]
  block = found[:block]

  name     = symbol_value(args[0])
  type     = nil
  options  = {}
  resolved = !name.nil?

  args[1..].each do |arg|
    if hash_node?(arg)
      evaluated = LiteralEvaluator.evaluate(arg)
      options   = evaluated.is_a?(Hash) ? evaluated : {}
      resolved  = false unless evaluated.is_a?(Hash) && !options.value?(LiteralEvaluator::UNRESOLVED)
    elsif type.nil?
      type = const_value(arg) || symbol_type_value(arg)
      resolved = false if type.nil?
    end
  end
```

— [`param_extractor.rb:96-114`](../lib/rails_openapi_generator/param_extractor.rb)

Three things happen:

1. The first argument is the parameter name. Always a symbol.
2. The next non-hash argument is the type. Either a constant like `String`, an `ActiveSupport::Numeric`, or the shorthand `:boolean` (recognized via the small `SYMBOL_TYPE_ALIASES` table).
3. The trailing hash is the options — `required:`, `in:`, `description:`, etc.

The `resolved` flag tracks whether *everything* came through cleanly. If the options hash has any unresolved value (e.g. `in: SomeRuntimeMethod.call`), we flip the flag. Downstream, that becomes a warning. We still emit the parameter — we just don't apply unresolvable constraints.

## Nested blocks

The interesting part of `ParamExtractor` is nesting. Real Rails apps write things like:

```ruby
param! :landing_page_setting, Hash, required: true do |h|
  h.param! :downloadable, :boolean, required: true
  h.param! :sections, Hash do |s|
    s.param! :logo, Hash do |logo|
      logo.param! :visible, :boolean, required: true
    end
  end
end
```

That's an OpenAPI nested object. The block parameter `h` is rebound at each level, and inside the block, `h.param!` (not bare `param!`) declares the next level.

```ruby
def nested_for(type, block, depth)
  return nil unless block && %w[Hash Array].include?(type)
  return nil if depth >= @max_depth

  block_vars = block_var_names(block)
  return nil if block_vars.empty?

  body = block_body(block)
  return nil if body.nil?

  nested_calls = extract_nested_calls(body, block_vars).map do |found|
    build_call(found, depth: depth + 1)
  end

  case type
  when "Hash"  then nested_calls
  when "Array" then nested_calls.last
  end
end
```

— [`param_extractor.rb:133-151`](../lib/rails_openapi_generator/param_extractor.rb)

`extract_nested_calls` walks the block body looking for `<block_var>.param! ...` — that's the load-bearing bit. We bind to the *block's parameter name*, not to a hardcoded `h`. That keeps user code idiomatic.

The recursion is bounded by `max_depth`, defaulting to 5. We picked 5 because it covers every real-world nested form we've seen and prevents pathological infinite recursion in the unlikely event of a cycle. The bound is configurable.

> **Aside: why `Array` keeps only the last nested call.**
> An `Array` `param!` with a block declares the *item shape*, not item N. The user typically writes a single `param!` inside the block. If they write multiple, the last one wins — matching `rails_param`'s runtime behavior. The `nested_calls.last` line above is the implementation of that decision.

## `SchemaMapper`

Once we have a `ParamCall`, mapping to OpenAPI is straightforward. The Ruby type maps to an OpenAPI `type` and optional `format`:

```ruby
TYPE_MAP = {
  "String" => { "type" => "string" },
  "Integer" => { "type" => "integer" },
  "Float" => { "type" => "number" },
  # ...
  "Date" => { "type" => "string", "format" => "date" },
  "DateTime" => { "type" => "string", "format" => "date-time" },
  "Time" => { "type" => "string", "format" => "date-time" }
}.freeze
```

— [`schema_mapper.rb:6-20`](../lib/rails_openapi_generator/schema_mapper.rb)

Constraints map to OpenAPI fields:

```ruby
def apply_constraints(schema, constraints)
  constraints.each do |key, value|
    case key
    when :in         then apply_inclusion(schema, value)
    when :min        then schema["minimum"] = value
    when :max        then schema["maximum"] = value
    when :min_length then schema["minLength"] = value
    when :max_length then schema["maxLength"] = value
    when :format     then schema["pattern"] = pattern_source(value) if pattern_source(value)
    when :blank      then schema["minLength"] = 1 if value == false && schema["type"] == "string"
    when :description then schema["description"] = value if value.is_a?(::String)
    end
  end
  schema
end
```

— [`schema_mapper.rb:33-47`](../lib/rails_openapi_generator/schema_mapper.rb)

`apply_inclusion` is where Range vs Array of enum values branches:

```ruby
def apply_inclusion(schema, value)
  case value
  when Range
    schema["minimum"] = value.first
    if value.exclude_end?
      schema["exclusiveMaximum"] = value.last
    else
      schema["maximum"] = value.last
    end
  when Array
    schema["enum"] = value
  end
end
```

— [`schema_mapper.rb:59-71`](../lib/rails_openapi_generator/schema_mapper.rb)

Notice `exclude_end?`. `rails_param` accepts both `1..100` (inclusive) and `1...100` (exclusive); we honor the difference because OpenAPI does.

The `blank: false` clause is taste, not necessity. The `rails_param` runtime treats `blank: false` as "no empty strings"; OpenAPI doesn't have a "non-blank" concept, but it does have `minLength: 1`, which is the closest equivalent. We do the translation.

## Where the parameters end up

`OperationBuilder` decides whether each parameter is a path param, a query param, or part of the request body:

```ruby
def build_parameters(route, param_calls, implicit)
  by_name = param_calls.each_with_object({}) { |call, map| map[call.name] = call if call.name }
  parameters = []

  route.path_params.each do |segment|
    call   = by_name[segment]
    schema = call ? @schema_mapper.map(call) : { "type" => "string" }
    parameters << build_parameter(name: segment, location: :path, required: true, schema: schema)
  end

  unless body_method?(route)
    non_path_calls(route, param_calls).each do |call|
      parameters << build_parameter(
        name: call.name, location: :query, required: call.required, schema: schema_for(call)
      )
    end
    implicit.each do |name|
      parameters << Parameter.new(name: name, location: :query, required: false, schema: {})
    end
  end

  parameters
end
```

— [`operation_builder.rb:73-95`](../lib/rails_openapi_generator/operation_builder.rb)

The rule: path segments are path params. For `GET`/`DELETE`, everything else is a query param. For `POST`/`PUT`/`PATCH`, everything else goes into the request body.

That last rule isn't an OpenAPI requirement. We made it because Rails apps overwhelmingly follow it. A `POST` with `param! :name, String` means "the name comes in the body." If a user actually wants a body-style POST with a query parameter, they're outside the slice we serve.

## Implicit params

A different, smaller story. Sometimes users don't write `param!` — they just write `params[:foo]` or `params.require(:bar)`. We pick those up via [`ImplicitParamScanner`](../lib/rails_openapi_generator/implicit_param_scanner.rb):

```ruby
STRONG_PARAM_METHODS = %w[require permit fetch dig].freeze
RAILS_INTERNAL_KEYS  = %w[controller action format].freeze
```

— [`implicit_param_scanner.rb:9-10`](../lib/rails_openapi_generator/implicit_param_scanner.rb)

Walking the action (plus its helpers — see chapter 8) we collect every key referenced as `params[:foo]` or `params.require(:foo)` or `permit(:a, :b)` etc., minus Rails' internal keys (`controller`, `action`, `format`).

These become parameters with an *empty schema* (`{}`):

```ruby
implicit.each do |name|
  parameters << Parameter.new(name: name, location: :query, required: false, schema: {})
end
```

— [`operation_builder.rb:89-91`](../lib/rails_openapi_generator/operation_builder.rb)

We can't know the type — we only see that the action *uses* `params[:foo]`. The user gets a permissive parameter that signals "this exists" without lying about its shape.

We did this for a specific real-world scenario: most legacy Rails apps don't use `rails_param`. Without implicit detection, the document for a normal Rails app would be almost empty.

## Try it yourself

In [`spec/fixtures/dummy/app/controllers/api/users_controller.rb`](../spec/fixtures/dummy/app/controllers/api/users_controller.rb), add this to the `index` action:

```ruby
param! :since, DateTime, description: "Only return users created after this timestamp"
```

Run the generator:

```sh
bundle exec rspec spec/integration/generate_all_endpoints_spec.rb
```

Open the generated document (write it to a temp path first by changing the spec). Look at `/api/users` GET. You should see a `since` query parameter, with `type: "string"` and `format: "date-time"`, *and* the description on the parameter object — not nested inside the schema.

Now change the type to `Hash` with a block:

```ruby
param! :filter, Hash do |f|
  f.param! :name, String, description: "User name to filter by"
  f.param! :role, String, in: %w[admin member]
end
```

Look at the output. Is the parameter a query param or a body? Why? (Hint: `GET` route.) Is this the *right* answer? (Hint: probably not. Real-world `Hash`-on-GET is rare; the [feature 008 spec](../specs/008-nested-param-blocks/spec.md) records the decision.)
