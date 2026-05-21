# 13. Where to go next

You've read the gem. This chapter is a map of the frontier: what the gem can't do yet, where the bodies are buried, and what a good first contribution looks like.

## The honest limits

The gem's design — static analysis, no execution (chapter 2) — fixes a hard ceiling. Some things are *fundamentally* out of reach, and some are merely *not built yet*. Knowing which is which is the most useful thing this chapter can give you.

**Fundamentally out of reach** (would require executing code, which we won't do):

- Response shapes that come from a runtime object: `render json: UserSerializer.new(user)`. We see the `render json:`, we emit a 200 with an empty `{}` body. To do better we'd have to run the serializer.
- Dynamically generated routes or actions (`define_method`, metaprogrammed controllers).
- Conditionals on runtime data that change the *type* of a response (not just its branches).

These aren't bugs. They're the price of the static approach. The right fix for a user hitting them is the **schema sidecar** (chapter 7) — an escape hatch we built precisely for "we can't infer this, let me write it by hand."

**Not built yet** (compatible with static analysis, just unimplemented):

- `components/schemas` with `$ref` reuse. Right now every schema is inlined. A `_user.json.jbuilder` rendered in ten places produces ten copies of the user schema. We *could* hoist shared schemas into `components` and `$ref` them. The information is all there; nobody's built the de-duplication pass.
- `security` schemes. We can see `before_action :authenticate` (chapter 8) — we just don't translate it into an OpenAPI `security` requirement.
- More `respond_to` formats. [`render_extractor.rb`](../lib/rails_openapi_generator/render_extractor.rb) maps only `json` and `html`:

  ```ruby
  FORMAT_CONTENT_TYPES = { "json" => "application/json", "html" => "text/html" }.freeze
  ```

  — [`render_extractor.rb:75`](../lib/rails_openapi_generator/render_extractor.rb)

  The comment right above says "A future feature MAY extend it." Adding `xml`, `csv`, `pdf` is a one-line table change plus a fixture and a test.

- Richer jbuilder coverage. The parser handles `extract!`, `set!`, `partial!`, `array!`, conditionals, and `case`. It does not handle `json.merge!` with a literal hash, or `cache!` blocks (those are in the IGNORED list). Each is a scoped addition to [`jbuilder_parser.rb`](../lib/rails_openapi_generator/jbuilder_parser.rb).

## Where the fragile code is

If you're going to break something, it'll probably be here:

1. **Ripper AST shapes.** Every file that calls `Ripper.sexp` hardcodes the array layout of nodes. When Ruby changes its grammar (rare, but it happens), these shapes can shift. The comments documenting each shape are your lifeline. The densest concentration is [`render_extractor.rb`](../lib/rails_openapi_generator/render_extractor.rb) and [`param_extractor.rb`](../lib/rails_openapi_generator/param_extractor.rb).

2. **The proc-handler resolution in [`rescue_from_resolver.rb`](../lib/rails_openapi_generator/rescue_from_resolver.rb).** It matches a block by its `source_location` line number against the AST. Line-number matching is inherently brittle. It's wrapped in a `rescue` so a miss degrades to "no 404 entry," but it's the first place to suspect if a `rescue_from X do ... end` stops contributing a response.

3. **The module-level `LiteralEvaluator.resolver`.** It makes the evaluator non-reentrant (chapter 5). If anyone ever tries to run two generations concurrently in one process, this will bite. Today nothing does.

## Good first contributions

Ordered by difficulty:

**Add a `respond_to` format.** Add `"xml" => "application/xml"` to `FORMAT_CONTENT_TYPES`, add a `respond_to`-with-xml action to the dummy app, write the assertion. You'll touch one constant, one fixture, one spec. This is the canonical "learn the loop" task.

**Add a jbuilder construct.** Pick something in the IGNORED list that *should* contribute (e.g. a literal `json.merge!({ status: "ok" })`), and teach `build_schema` to handle it. Scoped to [`jbuilder_parser.rb`](../lib/rails_openapi_generator/jbuilder_parser.rb), per the chapter-12 "lives in one file" discipline.

**Add a `SchemaMapper` constraint.** `rails_param` supports more options than we map. Find one we drop, map it to its OpenAPI equivalent in [`schema_mapper.rb`](../lib/rails_openapi_generator/schema_mapper.rb)'s `apply_constraints`. The `blank: false → minLength: 1` line is the template to copy.

**The big one: `components/schemas` extraction.** This is a real feature, not a warm-up. It needs a new pass that walks the assembled endpoints, finds identical schemas, hoists them into `components/schemas`, and rewrites the inline copies as `$ref`s. It touches `DocumentBuilder` and adds a new collaborator. Write the `specs/022-*/spec.md` first (chapter 12). This is where you'd graduate from reading the gem to extending it.

## How to find your way back in

When you return to this code in three months and have forgotten everything:

- **Start at [`generator.rb`](../lib/rails_openapi_generator/generator.rb).** `build_endpoint` is the whole program in 30 lines (chapter 5). Everything else hangs off it.
- **Use the feature numbers.** Grep `feature NNN` to jump from a code annotation to its design doc, or read [`CHANGELOG.md`](../CHANGELOG.md) to find which version added what (chapter 12).
- **Run the determinism and resilience specs first.** If those pass, the gem's two hardest invariants hold, and you can trust the rest.
- **Reread chapter 4.** The struct names are the vocabulary. If a chapter loses you, it's usually because a struct slipped your memory.

## A closing note on the shape of this gem

If there's one thing to carry away: this gem is small files doing one thing each, glued by a single orchestrator, defended by a "warn, never raise" policy, and held to byte-identical output. None of those four properties is an accident. Each is a response to a real constraint — the static-analysis ceiling, the CI-must-not-fail requirement, the diff-must-be-clean requirement, the contributions-from-strangers requirement.

You can disagree with any of them. But change one and you'll feel the others pull back. That tension — where the load-bearing decisions resist being moved — is the truest map of a codebase. Now you have it.

## Try it yourself

Do the canonical loop task: add `"csv" => "text/csv"` to `FORMAT_CONTENT_TYPES` in [`render_extractor.rb`](../lib/rails_openapi_generator/render_extractor.rb). Add an action to [`spec/fixtures/dummy/app/controllers/api/respond_to_controller.rb`](../spec/fixtures/dummy/app/controllers/api/respond_to_controller.rb) with a `respond_to` block that has a `format.csv`. Add a route for it. Write an integration assertion that the operation's 200 response has a `text/csv` content type. Make it pass.

Then read your own diff and ask: did it "live in one place"? If it sprawled, where, and could the architecture have absorbed it more cleanly? That question — asked of your own change — is the habit this whole book was trying to build.
