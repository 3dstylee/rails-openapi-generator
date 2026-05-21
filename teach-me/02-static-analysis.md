# 2. Why static analysis

The first sentence of the [README](../README.md) is the most important sentence in the gem:

> Generate an OpenAPI 3.1 document for a Rails app by static source analysis. No controller code is executed.

This chapter explains what that means and what it costs.

## The alternative we did not choose

There is a popular Ruby gem named [rswag](https://github.com/rswag/rswag) that asks you to write request specs annotated with the OpenAPI shape you want. It runs them. The annotations decorate real requests, and the test runner emits the document as a side effect.

That approach has a strong appeal: the requests really run, so the documented shape is the actual shape. Lying is hard. But it also has costs:

- Your CI must boot your app, hit a database, sign in test users, and execute every documented endpoint. That's slow.
- You write specs to get docs. The annotations are an extra surface to maintain, separate from the code.
- Coverage of error paths needs error-path specs. Real users don't enjoy writing those.

We took the other tradeoff. We never execute the controller. We read the code.

## The cost of static analysis

We can only see what is *literally written* in source. If your action has `render json: User.first.serializable_hash`, we know it returns JSON, but we cannot guess the shape — the call goes through an object whose contents are runtime data. Anywhere the user writes Ruby that depends on runtime state, our schema collapses to "any" (the empty schema `{}`).

We accept that. The README is honest about it:

> jbuilder template … Literal values carry `example`. Property names from `extract!` use `{}` (any).

The gem leans heavily on Ruby being a *literal-friendly* language. Rails encourages people to write things like `render json: { id: 1, name: "alice" }` in stubs and `param! :role, String, in: %w[admin member]` in validations. Each literal we can recover becomes signal in the output.

## The two tools

We use two parsers in tandem.

[Ripper](https://docs.ruby-lang.org/en/master/Ripper.html) is part of Ruby's standard library. It parses Ruby source into a tree of arrays — an "sexp." Each node starts with a symbol naming its shape. A literal integer `42` is `[:@int, "42", [line, col]]`. A method call `render json: { id: 1 }` is a `[:command, …]` with deeply nested children.

Ripper is verbose but stable. It ships with every Ruby version, so we don't pull in a gem. The cost is that the AST shape is undocumented enough that you'll see comments in our code like:

```ruby
# `:hash` node — node[1] is `[:assoclist_from_args, assocs]` or nil.
```

— [`literal_evaluator.rb:131`](../lib/rails_openapi_generator/literal_evaluator.rb)

Every file that touches an AST has a few comments like that. They're load-bearing — Ripper's docs are sparse, and the only way to remember the shape is to write it down.

[YARD](https://yardoc.org/) is the standard Ruby documentation gem. It also parses Ruby, but we use it for one thing only: extracting the comment block above each `def`. We could do it ourselves, but YARD already handles `@param`, `@return`, multi-paragraph blocks, and code fences, so we let it. See [`yard_parser.rb`](../lib/rails_openapi_generator/yard_parser.rb):

```ruby
YARD::Registry.clear
YARD.parse(file_path, [])
YARD::Registry.all(:method).each_with_object({}) do |object, result|
  text = object.docstring.to_s
  result[object.name.to_s] = text unless text.strip.empty?
end
```

That ten-line block is the entire reason we depend on YARD.

> **Aside: why not the `parser` gem?**
> [`parser`](https://github.com/whitequark/parser) produces a friendlier AST and is what RuboCop uses. We chose Ripper because (a) it ships with Ruby, no extra dependency; (b) it's frozen against Ruby's grammar — when Ruby ships a new syntax, Ripper handles it the same release. The cost is the array-of-arrays shape. We pay that cost in [`render_extractor.rb`](../lib/rails_openapi_generator/render_extractor.rb), the densest file in the gem, but only there.

## The `LiteralEvaluator`

The shared bottleneck for every "is this a literal we can read?" question is [`lib/rails_openapi_generator/literal_evaluator.rb`](../lib/rails_openapi_generator/literal_evaluator.rb). It's a stateless module — `LiteralEvaluator.evaluate(ast_node)` returns either a real Ruby value or the sentinel `UNRESOLVED`:

```ruby
UNRESOLVED = :__rog_unresolved__
```

— [`literal_evaluator.rb:9`](../lib/rails_openapi_generator/literal_evaluator.rb)

We use a symbol with an obscure name so it can never collide with a user value. (No one writes `:__rog_unresolved__` in their own code. If they do, that's their problem.)

The dispatch is one big `case` over Ripper node types:

```ruby
case node[0]
when :@int             then Integer(node[1], exception: false) || UNRESOLVED
when :@float           then Float(node[1], exception: false) || UNRESOLVED
when :string_literal   then string_value(node)
when :symbol_literal, :symbol, :dyna_symbol then symbol_value(node)
when :array            then array_value(node[1])
when :hash             then hash_value(node[1])
when :var_ref          then var_ref_value(node[1])
when :const_path_ref   then const_path_value(node)
# ...
else UNRESOLVED
end
```

— [`literal_evaluator.rb:23-43`](../lib/rails_openapi_generator/literal_evaluator.rb)

That `else UNRESOLVED` is the safety net. Anything we don't recognize is unresolved — never crashed, never invented.

The evaluator also resolves *constants*. When a user writes `param! :status, String, in: Order::STATUSES`, the `Order::STATUSES` reference goes through `const_path_value`, which builds the qualified name `"Order::STATUSES"` and asks [`ConstantResolver`](../lib/rails_openapi_generator/constant_resolver.rb) to look it up. We decided this was worth the cost: Rails apps love to put enums in constants, and emitting `enum: []` instead of `enum: ["paid","shipped","cancelled"]` would be sad.

But: we will not run *any* expression. `Order::STATUSES.sort` is unresolved. `Order::STATUSES + ["new"]` is unresolved. We resolve names, not code.

## The `UNRESOLVED` discipline

`UNRESOLVED` is the linchpin of the "warn, never raise" policy you'll see in chapter 10. Every layer above the evaluator checks for it and degrades gracefully:

- In [`render_extractor.rb`](../lib/rails_openapi_generator/render_extractor.rb), an `UNRESOLVED` render body yields a render-site with `schema: nil` — we know the status, we don't know the body.
- In [`jbuilder_parser.rb`](../lib/rails_openapi_generator/jbuilder_parser.rb), an `UNRESOLVED` jbuilder value becomes the permissive empty schema `{}` ("any value").
- In [`param_extractor.rb`](../lib/rails_openapi_generator/param_extractor.rb), an `UNRESOLVED` `param!` argument flips the `fully_resolved` flag, which becomes a warning in the run report.

We decided this early and stuck to it: any code path that can encounter user code must handle non-literals without raising. Chapter 10 covers the consequences for error handling.

> **Aside: a peculiar Ruby footgun.**
> `LiteralEvaluator::UNRESOLVED` is itself a Symbol. Symbol literals in user source resolve to Strings (because that's what [`string_value`](../lib/rails_openapi_generator/literal_evaluator.rb) returns for `:symbol_literal`), so a "Symbol" appearing later in the pipeline can only ever be our sentinel. That invariant matters in `schema_for`:
>
> ```ruby
> return {} if value == UNRESOLVED
>
> case value
> when ::String then { "type" => "string",  "example" => value }
> ```
>
> — [`literal_evaluator.rb:179-181`](../lib/rails_openapi_generator/literal_evaluator.rb)
>
> The early return is not paranoia — without it, the sentinel would fall through, miss every typed branch, and produce `{}`. We comment this in the source.

## Try it yourself

Open `irb` from the project root and load the gem:

```ruby
$LOAD_PATH.unshift("lib")
require "rails_openapi_generator"
require "ripper"
```

Try these in order, looking at each result:

```ruby
LiteralEvaluator.evaluate(Ripper.sexp("42")[1][0])
LiteralEvaluator.evaluate(Ripper.sexp("[1, 2, 3]")[1][0])
LiteralEvaluator.evaluate(Ripper.sexp("{ a: 1, b: User.first }")[1][0])
LiteralEvaluator.evaluate(Ripper.sexp("x + 1")[1][0])
```

Now write *one* expression you expect to evaluate, that doesn't, and explain why looking at the case dispatch. (Don't peek at `const_path_value`. The interesting failure isn't there.)
