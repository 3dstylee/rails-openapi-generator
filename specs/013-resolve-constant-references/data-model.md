# Phase 1 Data Model: Resolve Constant References

The feature adds one new class and extends one existing module with
three AST node cases. No existing struct changes shape. No new field
flows through the downstream pipeline — the resolver returns the
same Ruby values `LiteralEvaluator` already produces from literal
AST nodes.

## New entity: `ConstantResolver` (lib/rails_openapi_generator/constant_resolver.rb)

A thin wrapper around `Object.const_get` with caching, broad
error rescue, and a schema-compatibility filter.

| Member | Type | Description |
|--------|------|-------------|
| `@cache` | `Hash<String, Object \| Symbol>` | Per-instance map of qualified name → resolved value or UNRESOLVED. |

### Public methods

| Method | Returns | Behavior |
|--------|---------|----------|
| `resolve(qualified_name)` | resolved value, or `LiteralEvaluator::UNRESOLVED` | Looks up the constant via `Object.const_get(name, true)`. Returns from cache on repeated calls. Catches `StandardError` and `LoadError` (silently → UNRESOLVED). Validates the resolved value via `schema_compatible?`; non-compatible values are also UNRESOLVED. |

### Private predicates

| Predicate | Compatible types |
|-----------|------------------|
| `schema_compatible?(value)` | `String`, `Symbol`, `Integer`, `Float`, `true`, `false`; `Range` of `Integer` or `Float`; `Regexp`; `Array` of recursively-compatible values; `Hash` with `String`/`Symbol` keys and recursively-compatible values. Anything else → `false`. |

### Lifecycle

- Constructed by `Generator#setup_pipeline` once per generator run.
- Stored on `LiteralEvaluator.resolver` (module-level
  accessor — research R7), so `LiteralEvaluator.evaluate(node)`
  can reach it without threading a parameter through every
  callsite.
- Reset to `nil` at the end of the run (or simply replaced on the
  next `setup_pipeline` — the previous instance becomes
  garbage).

## Modified entity: `LiteralEvaluator` (lib/rails_openapi_generator/literal_evaluator.rb)

Three new node cases on `LiteralEvaluator.evaluate`:

| Node shape (Ripper) | Source form | New behavior |
|---------------------|-------------|--------------|
| `[:var_ref, [:@const, NAME, ...]]` | `FOO` | `resolver.resolve(NAME)` when the resolver is set; else UNRESOLVED. |
| `[:const_path_ref, LEFT, [:@const, NAME, ...]]` | `A::B::C` | Build the qualified name by recursively unwrapping `LEFT`, joining segments with `::`. Pass to `resolver.resolve`. |
| `[:top_const_ref, [:@const, NAME, ...]]` | `::FOO` | `resolver.resolve(NAME)` (top-level resolution is the default). |

A new module-level accessor:

| Accessor | Description |
|----------|-------------|
| `LiteralEvaluator.resolver` / `resolver=` | The current `ConstantResolver` instance (or `nil`). Set by `Generator#setup_pipeline`; left `nil` in unit specs that don't opt into resolution. |

### Qualified-name building (recursive)

```text
qualified_name(node):
  case node[0]
  when :var_ref, :top_const_ref → node[1][1]            # the bare const name
  when :const_path_ref          → qualified_name(node[1]) + "::" + node[2][1]
  end
```

A `:var_ref` carrying a non-`:@const` child (e.g. `:@ident` for a
local variable) is NOT a constant reference and is left to today's
existing `:var_ref → keyword_value` branch (which handles
`true`/`false`/`nil`).

## Value flow (input → output)

For `param! :mood, String, in: AutoPhotoVhs::EnqueueFurnitureGenerationService::MOODS`:

```text
ParamExtractor sees the param! call.
  ↓ args[1..] includes `[:bare_assoc_hash, [...assoc nodes...]]`.
  ↓ LiteralEvaluator.evaluate(assoc_hash):
    ↓ For the `:in => <const_path_ref>` association:
      – Evaluate the value node, which is `:const_path_ref`.
      – Build qualified name `"AutoPhotoVhs::EnqueueFurnitureGenerationService::MOODS"`.
      – Call `LiteralEvaluator.resolver.resolve(name)`.
      – Resolver does `Object.const_get(name, true)` → returns
        `["modern", "classic", "minimalist", "scandinavian", "industrial"]`.
      – `schema_compatible?` accepts (Array of Strings).
      – Cache stores the result; return the Array.
    ↓ Hash becomes `{ in: ["modern", "classic", ...] }` — fully resolved.
  ↓ ParamCall is built with `constraints: { in: [...] }` and
    `fully_resolved: true`.

SchemaMapper.map(param_call) (unchanged):
  ↓ Sees `in:` is an Array → emits `enum: [...]` on the schema.

OperationBuilder emits the parameter; DocumentBuilder fans it
into the OpenAPI document. No further code change.
```

## Cache key / value table

| Cache key | Cache value | Meaning |
|-----------|-------------|---------|
| `"MOODS"` | `["a", "b", "c"]` | Literal Array of Strings, schema-compatible, used as-is. |
| `"A::B::RANGE"` | `1..100` | Integer Range, schema-compatible. |
| `"A::B::PATTERN"` | `/regex/` | Regexp, schema-compatible. |
| `"A::B::CLASS_REF"` | `LiteralEvaluator::UNRESOLVED` | Resolved value is a class — not schema-compatible. |
| `"A::B::MISSING"` | `LiteralEvaluator::UNRESOLVED` | `NameError` — rescued. |
| `"A::B::BROKEN_AUTOLOAD"` | `LiteralEvaluator::UNRESOLVED` | `LoadError` — rescued. |

## Backward compatibility

- The new node cases ONLY fire when `LiteralEvaluator.resolver`
  is set. Unit specs that test `LiteralEvaluator` in isolation
  (without setting a resolver) see UNRESOLVED for constant
  references — exactly the same value they saw before this
  feature.
- For host code WITH no constant references in any `param!`
  call, the new evaluator paths are never hit. Output is
  byte-identical (SC-004).
- For host code WITH constant references whose resolved values
  are schema-compatible, the `enum:` / `minimum:`/`maximum:` /
  `pattern:` newly appears on the parameter schema. The
  parameter's name, type, and `required` flag continue to be
  documented as before.
- For host code WITH constant references whose resolved values
  are NOT schema-compatible (or unloadable), output is
  byte-identical to today: the constraint is dropped, the
  "non-literal param! arguments" warning continues to fire.
