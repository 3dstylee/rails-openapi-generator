# Phase 1 Data Model: Nested Parameter Blocks

The feature adds one optional field to one existing struct
(`ParamCall`) and changes the schema-tree assembly in
`OperationBuilder`. No new struct, no schema-mapper change, no
new top-level class.

## Modified entity: `ParamCall` (lib/rails_openapi_generator/param_extractor.rb)

| Field | Type | Existed? | Description |
|-------|------|----------|-------------|
| `name` | String / nil | yes | Parameter name (a symbol stringified). Nil for an Array's item declaration (no item name; only a shape). |
| `type` | String / nil | yes | The literal type name (e.g. `"String"`, `"Hash"`, `"Array"`). |
| `required` | Boolean | yes | Whether the parameter is required. |
| `constraints` | Hash | yes | Resolved option-hash values (e.g. `{in: [...], min: 0}`). |
| `fully_resolved` | Boolean | yes | True when every argument was statically known. |
| **`nested`** | **Array<ParamCall> / ParamCall / nil** | **NEW** | For a `Hash` with a block, an array of nested `ParamCall` objects (the object's properties). For an `Array` with a block, a single `ParamCall` (the items' shape). Nil otherwise — today's flat case. |

### Validation rules

- `nested` is non-nil ONLY when `type` is `"Hash"` or `"Array"`
  AND a do-block was present on the `param!` call. A `param!` on
  a `String`/other type that happens to have a block leaves
  `nested: nil` (the block is ignored, per FR-008).
- For `type == "Hash"`, `nested` is `Array<ParamCall>` (possibly
  empty if the block declares no nested `param!`s; in that case
  the schema falls back to a bare `object` per FR-007).
- For `type == "Array"`, `nested` is a single `ParamCall` (or
  nil if no item declaration; falls back to a bare `array`).
- Each nested `ParamCall` is itself a full `ParamCall` — its own
  `nested:` may be set, recursively, up to
  `method_resolution_depth`.

## ParamExtractor flow (new pipeline)

```text
find_param_calls(action_node, depth: 0):
  ↓ Visit every node looking for param! call shapes:
    – :command with :@ident "param!" → flat call (today).
    – :method_add_arg + :fcall :@ident "param!" → flat call (today).
    – :method_add_block wrapping the above → call WITH a block.
  ↓ For each detected call, capture (args, block_node) and
    delegate to build_call(args, block_node:, depth:).
  ↓ When the call has a block AND type is Hash/Array AND
    depth < method_resolution_depth:
    a. Capture block param names from
       [:block_var, [:params, [[:@ident, NAME, ...], ...]], ...]
    b. Walk the block body for :command_call nodes whose
       receiver is :var_ref matching one of the block-param names
       and whose method name is :@ident "param!".
    c. For each match, recursively build_call(inner_args,
       inner_block, depth + 1).
    d. Hash → store the list of resulting ParamCalls in `nested`;
       Array → store the LAST resulting ParamCall as the single
       items shape (R5).
  ↓ Returns: a flat list of TOP-LEVEL ParamCalls, each with its
    own `nested:` tree.
```

## OperationBuilder flow (new emission)

For a request body (`build_request_body`):

```text
Iterate top-level ParamCalls (non-path) sorted by name.
For each:
  ↓ schema = schema_for_call(call)
  ↓ properties[call.name] = schema

schema_for_call(call):
  ↓ flat_schema = SchemaMapper.map(call)         # unchanged
  ↓ if call.nested.nil?
      → flat_schema
    elsif call.type == "Hash"
      → flat_schema.merge(
          "type" => "object",
          "properties" => sorted_nested_properties(call.nested)
        )
    elsif call.type == "Array"
      → flat_schema.merge(
          "type" => "array",
          "items" => schema_for_call(call.nested)
        )

sorted_nested_properties(list):
  ↓ list.map { |nested_call|
      [nested_call.name, schema_for_call(nested_call)]
    }.sort.to_h
```

Recursion is naturally bounded — the `nested:` tree itself is
already bounded by `method_resolution_depth` during extraction.

## Construction examples

### Example 1: Hash with two scalar fields (US1)

Source:

```ruby
param! :q, Hash do |q|
  q.param! :keyword, String
  q.param! :page,    Integer
end
```

ParamCalls:

```text
ParamCall(name: "q", type: "Hash", nested: [
  ParamCall(name: "keyword", type: "String", nested: nil),
  ParamCall(name: "page",    type: "Integer", nested: nil)
])
```

Emitted schema fragment:

```yaml
q:
  type: object
  properties:
    keyword:
      type: string
    page:
      type: integer
```

### Example 2: Array of String with constant `in:` (US2 — the user's report)

Source:

```ruby
param! :moods, Array do |p, i|
  p.param! i, String, in: AutoPhotoVhs::EnqueueFurnitureGenerationService::MOODS
end
```

ParamCalls:

```text
ParamCall(name: "moods", type: "Array", nested:
  ParamCall(name: nil, type: "String", constraints: {in: [<MOODS values>]}, nested: nil)
)
```

Emitted schema fragment:

```yaml
moods:
  type: array
  items:
    type: string
    enum: [modern, classic, minimalist, scandinavian, industrial]
```

The constant resolution is inherited from feature 013 — no extra
work in this feature.

### Example 3: Deep nesting (US3)

Source:

```ruby
param! :wrapper, Hash do |w|
  w.param! :inner, Hash do |i|
    i.param! :leaf, Integer
  end
end
```

ParamCalls:

```text
ParamCall(name: "wrapper", type: "Hash", nested: [
  ParamCall(name: "inner", type: "Hash", nested: [
    ParamCall(name: "leaf", type: "Integer", nested: nil)
  ])
])
```

Emitted schema fragment:

```yaml
wrapper:
  type: object
  properties:
    inner:
      type: object
      properties:
        leaf:
          type: integer
```

Depth bound: the descent stops when `depth >= method_resolution_depth`. At that point the parent emits a bare `object` / `array` schema (no `properties:` / `items:`), preserving forward progress on the rest of the document (FR-005, SC-004).

## Backward compatibility (SC-005)

- A `ParamCall` whose `nested:` is `nil` is emitted exactly as
  today — `OperationBuilder` reads the flat `SchemaMapper.map`
  output and uses it directly.
- The new field defaults to `nil` on every `ParamCall.new` call
  that does not explicitly set it.
- For the dummy app's existing `param!`-using endpoints
  (`api/users#index`'s `per_page`, etc.), no block is present →
  no nested tree → no change in output.

## Per-status / per-route impact summary

| Operation shape | Pre-0.13.0 | After |
|-----------------|------------|-------|
| Flat `param!` (no block) | byte-identical | byte-identical |
| `param! :h, Hash do |q| q.param! :a, String; q.param! :b, Integer end` | `h: { type: object }` | `h: { type: object, properties: { a: { type: string }, b: { type: integer } } }` |
| `param! :a, Array do |p, i| p.param! i, String, in: Module::CONSTANT end` | `a: { type: array }` | `a: { type: array, items: { type: string, enum: [resolved values] } }` |
| `param! :h, Hash do |q| q.param! :inner, Hash do |i| i.param! :leaf, Integer end end` | `h: { type: object }` | `h: { type: object, properties: { inner: { type: object, properties: { leaf: { type: integer } } } } }` |
| `param! :h, Hash do |q| end` (empty block) | byte-identical | byte-identical (FR-007) |
| `param! :s, String do |s| s.param! :x, Integer end` (block on non-Hash/Array) | byte-identical | byte-identical (FR-008) |
| Beyond depth bound | error / runaway | descent stops at bound; over-depth subtree emitted as bare object/array; document still valid (FR-005, SC-004) |
