# 8. Following the code

So far we've inspected the action body. But Rails actions delegate. They call helper methods. They run `before_action` callbacks. They have `rescue_from` handlers. A real response shape often lives two methods away from the action.

This chapter is about how we statically *follow* a call from the action into the method it invokes — across the whole controller ancestor chain, including concerns and the parent `ApplicationController`.

Five files do this work, and they all rest on one foundation: `MethodResolver`.

## `MethodResolver`: the foundation

The hard part of following a call is: given `send_pdf` called inside `download`, *which file and line is `send_pdf` defined in?* In Ruby this is genuinely hard to answer statically — the method might be in the controller, a parent, a module, a concern. Method lookup follows the ancestor chain.

We don't reimplement Ruby's method lookup. We *borrow* it:

```ruby
def resolve(controller_class, method_name)
  return nil if controller_class.nil? || method_name.nil?

  unbound = unbound_method(controller_class, method_name)
  return nil if unbound.nil?

  file, line = unbound.source_location
  return nil if file.nil? || !app_file?(file) || !File.file?(file)

  node = method_node(file, method_name.to_s)
  node && ResolvedMethod.new(name: method_name.to_s, node: node, location: "#{file}:#{line}")
end
```

— [`method_resolver.rb:21-32`](../lib/rails_openapi_generator/method_resolver.rb)

`controller_class.instance_method(method_name)` returns an `UnboundMethod`, and `.source_location` tells us the file and line. Ruby has already done the ancestor walk for us — `instance_method` resolves through modules and superclasses exactly as a real call would.

This is a *small* cheat on "no code execution." We load the controller class (so Ruby can reflect on it) but we never *call* the action. Loading a class runs its class body, which is benign (`before_action :foo`, `rescue_from X`). Calling an action runs request logic, which is not. We draw the line at "load the class, don't call the methods."

The `app_file?` guard is critical:

```ruby
def app_file?(file)
  return false if @app_root.nil?

  file.start_with?("#{@app_root}/")
end
```

— [`method_resolver.rb:52-56`](../lib/rails_openapi_generator/method_resolver.rb)

If a method resolves into a gem or the framework (e.g. `render` itself, defined in ActionController), we treat it as *unresolvable*. We only follow methods defined in the user's app. We don't want to wander into Rails internals — they're not the user's response shape, and they're a bottomless well.

## `ControllerMethodWalker`: breadth, bounded

The simplest walker. Given an action, return every reachable method body — the action plus every receiverless helper it calls, recursively:

```ruby
def collect(controller_class, node, depth, visited, bodies)
  bodies << node
  return if depth >= @max_depth || controller_class.nil?

  self.class.receiverless_call_names(node).uniq.each do |name|
    resolved = @method_resolver.resolve(controller_class, name)
    next if resolved.nil? || visited.include?(resolved.location)

    visited.add(resolved.location)
    collect(controller_class, resolved.node, depth + 1, visited, bodies)
  end
end
```

— [`controller_method_walker.rb:41-52`](../lib/rails_openapi_generator/controller_method_walker.rb)

Two guards, both load-bearing:

- `depth >= @max_depth` — bounded recursion. Defaults to 5. A controller with deeply chained helpers won't loop forever.
- `visited.include?(resolved.location)` — cycle guard. If `a` calls `b` calls `a`, we visit each location once. The dummy app has a `reports#cyclic` action that exercises exactly this.

"Receiverless" means we only follow `foo` and `foo(x)` and `foo bar` — calls with no explicit receiver, which in a controller resolve to `self`. We do *not* follow `user.serialize` — that's a method on some other object, and we can't know its class statically.

```ruby
def self.receiverless_call_names(node, names = [])
  return names unless node.is_a?(Array)

  if %i[command vcall fcall].include?(node[0])
    ident = node[1]
    names << ident[1] if ident.is_a?(Array) && ident[0] == :@ident
  end

  node.each { |child| receiverless_call_names(child, names) if child.is_a?(Array) }
  names
end
```

— [`controller_method_walker.rb:27-37`](../lib/rails_openapi_generator/controller_method_walker.rb)

`:command` (`foo bar`), `:vcall` (`foo`), `:fcall` (`foo(bar)`) — the three receiverless call shapes in Ripper.

`WrapperDownloadResolver` and `ImplicitParamScanner` both ride on this walker. The download resolver asks "does any reachable body call `send_file`?" The implicit scanner asks "what keys does any reachable body read from `params`?" Both reuse the walk; neither reimplements it.

## `HelperBindingWalker`: depth, with argument substitution

The cleverest file in the gem. Consider:

```ruby
def create
  render_error(status: :forbidden, code: "FORBIDDEN", message: "...")
end

def render_error(status:, code:, message:)
  render json: { error: { code: code, message: message } }, status: status
end
```

The response shape (`{ error: { code, message } }`) and the status (`403`) are split between two methods. The `code` and `message` *values* are passed in at the call site as literals. To recover the schema, we have to substitute the call-site literals into the helper body before extracting renders.

That's what `HelperBindingWalker` does. It walks each helper call, binds the call's literal arguments to the helper's parameter names, and produces a *substituted* AST where every reference to a bound parameter has been replaced by the literal:

```ruby
def walk(controller_class, node, depth, bodies)
  return if depth >= @max_depth

  receiverless_calls(node).each do |call|
    resolved = @method_resolver.resolve(controller_class, call[:name])
    next if resolved.nil?

    bindings = bind_args(resolved.node, call[:args])
    substituted = substitute(body_of(resolved.node), bindings)
    bodies << substituted
    walk(controller_class, substituted, depth + 1, bodies)
  end
end
```

— [`helper_binding_walker.rb:35-47`](../lib/rails_openapi_generator/helper_binding_walker.rb)

The substitution itself is a non-mutating AST rewrite:

```ruby
def substitute(node, bindings)
  return node if bindings.empty?
  return node unless node.is_a?(Array)

  if var_ref_ident?(node)
    name = node[1][1]
    return bindings.fetch(name, node)
  end

  node.map { |child| child.is_a?(Array) ? substitute(child, bindings) : child }
end
```

— [`helper_binding_walker.rb:197-207`](../lib/rails_openapi_generator/helper_binding_walker.rb)

Every `[:var_ref, [:@ident, "code"]]` in the helper body whose name is bound (`code` → the AST for `"FORBIDDEN"`) gets replaced by the literal node. Then when `RenderExtractor` runs on the substituted body, `render json: { error: { code: code } }` reads as `render json: { error: { code: "FORBIDDEN" } }` — a recoverable literal.

The bindings *compose* through nested calls (line 45's recursive `walk` runs against the already-substituted body), so a literal passed two levels deep still reaches the render. This was [feature 018](../specs/018-helper-arg-propagation/); the docstring at the top of the file is worth reading.

Why is binding non-mutating? Because the input AST is shared and cached. `YardParser` caches one AST per file. If we mutated it, the next route that touches the same helper would see a poisoned tree. The comment on `substitute` records this.

> **Aside: the two walkers are different on purpose.**
> `ControllerMethodWalker` collects bodies as-is, no substitution, and dedups by location (cycle guard). `HelperBindingWalker` substitutes arguments and does *not* dedup by location — because a helper called twice with different literals must contribute two different substituted bodies. The contrast is intentional: one answers "what code is reachable?", the other answers "what does each *call* of that code resolve to?"

## `BeforeActionResolver` and `RescueFromResolver`

These two answer: "Rails will invoke this method for me — what does it render?"

A `before_action :authenticate` can `render json: { error: ... }, status: 401` and `head` the request, contributing a 401 response to *every* action it applies to. A `rescue_from RecordNotFound, with: :render_404` contributes a 404 to every action on the controller.

`BeforeActionResolver` reads Rails' own callback chain via reflection:

```ruby
chain = controller_class._process_action_callbacks
filters = own_source_filters(controller_class)

chain.filter_map { |callback| build_callback(callback, controller_class, filters) }
```

— [`before_action_resolver.rb:43-46`](../lib/rails_openapi_generator/before_action_resolver.rb)

`_process_action_callbacks` is Rails' internal API for the registered `before_action`s — it already knows the resolved chain including inherited callbacks. But it does *not* cleanly expose `only:`/`except:` filters, so we re-parse the controller's *own* source to recover those:

```ruby
def applies_to?(action_name)
  return false if only && !only.include?(action_name.to_s)
  return false if except&.include?(action_name.to_s)

  true
end
```

— [`before_action_resolver.rb:18-23`](../lib/rails_openapi_generator/before_action_resolver.rb)

So a `before_action :authenticate, except: [:index]` contributes its 401 to every action *except* `index`. We had to combine Rails reflection (the chain) with source parsing (the filters), because neither alone gives the full picture.

`RescueFromResolver` is similar but reads `controller_class.rescue_handlers`. A handler can be a Symbol (method name) or a Proc (inline block). The Symbol case resolves via `MethodResolver`; the Proc case is harder — we have to find the `rescue_from X do |e| ... end` block in source by matching the proc's `source_location` line:

```ruby
def resolve_proc_handler(proc_handler)
  file, line = proc_handler.source_location
  return nil if file.nil? || line.nil? || !File.file?(file)

  sexp = Ripper.sexp(File.read(file))
  return nil if sexp.nil?

  find_rescue_from_block(sexp, line)
rescue StandardError
  nil
end
```

— [`rescue_from_resolver.rb:71-81`](../lib/rails_openapi_generator/rescue_from_resolver.rb)

The proc-handler path is the most fragile code in the gem — it depends on line-number matching against the AST. It's wrapped in a `rescue StandardError` returning `nil`, because a missed rescue handler is a missing 404 entry, not a crash.

## How the Generator stitches them together

The generator's `collect_extra_sites` calls all three:

```ruby
def collect_extra_sites(route, controller_class, action_source)
  action_node = action_source&.method_node
  return [] if action_node.nil? || controller_class.nil?

  helper_sites = helper_render_sites(controller_class, action_node)
  callback_sites = before_action_render_sites(controller_class, route.action)
  rescue_sites = rescue_from_render_sites(controller_class)
  helper_sites + callback_sites + rescue_sites
end
```

— [`generator.rb:182-190`](../lib/rails_openapi_generator/generator.rb)

The result is "extra sites" — render sites reachable through helpers, callbacks, and rescue handlers. These merge with the action's own sites in `ResponseBuilder`, producing the multi-status response set from chapter 7.

## Try it yourself

Open [`spec/fixtures/dummy/app/controllers/api/reports_controller.rb`](../spec/fixtures/dummy/app/controllers/api/reports_controller.rb). Find the `chained` action and trace, by hand, the helper calls it makes until you reach a `send_file` or `send_data`. Count the depth. Now look at [`spec/fixtures/dummy/app/controllers/api/reports_controller.rb`](../spec/fixtures/dummy/app/controllers/api/reports_controller.rb)'s `cyclic` action — convince yourself the cycle guard in `ControllerMethodWalker` keeps it terminating.

Then: set `config.method_resolution_depth = 1` (in a quick script using `RailsOpenapiGenerator::Configuration`) and regenerate. Does `reports/chained` still classify as a file download? Why or why not?
