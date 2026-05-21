# 12. Spec-driven development

This chapter is about *how the codebase came to be shaped this way* — not the code, but the method. If you only read one chapter to understand why the gem has thirty small files instead of three big ones, read this one.

## The `specs/` directory

Twenty-one numbered folders sit at the repo root in [`specs/`](../specs/):

```
specs/
├── 001-openapi-rake-generator/
├── 002-response-bodies/
├── 003-html-page-endpoints/
├── ...
├── 020-schema-sidecars/
└── 021-literal-examples/
```

Each is a *feature* — one increment of capability — and each follows the same internal structure:

```
specs/016-jbuilder-partials-and-case-branches/
├── spec.md         # what to build, in user terms — the contract
├── plan.md         # how to build it — the technical approach
├── research.md     # decisions and alternatives considered
├── tasks.md        # the ordered checklist of work
├── quickstart.md   # how to verify it works
├── contracts/      # data shapes, where relevant
└── checklists/
```

This is the [Spec Kit](https://github.com/github/spec-kit) workflow — the same one driving the `speckit-*` skills available in this repo. The idea: write the spec before the code, plan before implementing, and keep a durable record of *why*.

## What a spec looks like

[`016/spec.md`](../specs/016-jbuilder-partials-and-case-branches/spec.md) opens with the user's actual request and the problem in user terms:

> today the parser handles `json.partial!` and `json.array!` partials, but it does NOT handle the equivalent shorthand `json.today_logs @today_logs, partial: "activity_log", as: :activity_log`. … The user reported this on a real fixture with 4 sibling keys all referencing the same partial.

Notice what's there: a concrete real-world trigger, the observable symptom (keys become permissive `{}`), and a priority. The spec is written from the *outside* — it describes behavior, not implementation. A user story (P1) describes the success condition without naming a single Ruby class.

This is deliberate. The spec is the contract. If you read `016/spec.md` and then look at the generated document, you can check whether the feature delivered — without reading `jbuilder_parser.rb` at all.

## What a plan looks like

[`016/plan.md`](../specs/016-jbuilder-partials-and-case-branches/plan.md) is where implementation strategy lives:

> Two tightly-scoped improvements to `lib/rails_openapi_generator/jbuilder_parser.rb`:
> 1. `json.<key> @collection, partial: "name"` resolution — `add_property` gains a check for a literal `partial:` option …
> 2. `case` / `when` branch merging — `visit_statement` adds `:case` to the list of conditional shapes …
>
> Both improvements live in one file. No other file changes. No new class, no new dependency, no new configuration.

The plan names the files, the methods, and — critically — the *boundaries*: "both improvements live in one file." That sentence is doing real work. It's a commitment to scope. A feature that "lives in one file" doesn't ripple. When you read the plan and then `git log` the feature, the diff should match the plan's claimed footprint.

This is why the gem has so many small, single-purpose files. Each was added or extended by a feature whose plan committed to a narrow footprint. The architecture is the *accumulated residue of scoped plans*. `jbuilder_parser.rb` handles jbuilder and nothing else, because every jbuilder feature's plan said "this lives in the jbuilder parser."

## Why this shapes the code so strongly

Three consequences you can see in the codebase:

**Single responsibility, enforced by process.** When feature 011 needed template-render-in-helpers support, it didn't bolt logic onto an existing class — it added [`view_locator.rb`](../lib/rails_openapi_generator/view_locator.rb) and extended `RenderSite` with a `template_name` field. The plan's "where does this live?" question forces a home for every change.

**Backward compatibility as a first-class concern.** Specs routinely include a clause like "flat ParamCalls emit byte-identical schemas to pre-0.13.0." The [`operation_builder.rb`](../lib/rails_openapi_generator/operation_builder.rb) comment quotes it:

```ruby
# Flat ParamCalls (`nested: nil`) emit byte-identical schemas to pre-0.13.0.
```

— [`operation_builder.rb:133`](../lib/rails_openapi_generator/operation_builder.rb)

That's a spec acceptance criterion, transcribed into the code as a guard against regression. The feature specs become the regression specs (chapter 11).

**Decisions are recorded, not re-litigated.** When you wonder "why does the jbuilder parser *union* conditional branches instead of emitting a `oneOf`?", the answer is in a `research.md`, not in someone's memory. The `specs/` folders are the project's institutional memory.

## The feature-number through-line

The numbering is a spine you can follow across the whole repo:

| Layer | Artifact |
|---|---|
| Design | `specs/016-jbuilder-partials-and-case-branches/` |
| Code comment | `(feature 016)` annotations in `jbuilder_parser.rb` |
| Test | `spec/integration/jbuilder_partials_and_case_branches_spec.rb` |
| Changelog | the `0.x.0` entry for feature 016 in [`CHANGELOG.md`](../CHANGELOG.md) |

Grep the codebase for `feature 016` and you'll find the code annotations. Grep `specs/016` and you'll find the design. The number ties them together. When you pick up a bug in a feature, this chain is how you reconstruct the original intent in minutes instead of hours.

> **Aside: the cost of this discipline.**
> Spec-driven development is not free. Writing `spec.md` + `plan.md` + `research.md` before code is slower for a one-line fix, and overkill for a typo. The payoff is in a codebase meant to live a long time and accept contributions from people who weren't in the original conversation. For a throwaway script, skip it. For a gem other people depend on, the up-front cost buys you a code base that explains itself. This gem made that bet.

## How to use this when you contribute

When you add a feature:

1. Read the most recent `specs/NNN-*/` folder to learn the house style.
2. Create `specs/NNN+1-your-feature/spec.md` describing the behavior in user terms.
3. Write `plan.md` committing to a footprint. Resist scope creep here — it's cheaper to say no in the plan than to unwind code.
4. Add the fixture (a dummy-app controller/view) and the integration spec.
5. Implement, annotating non-obvious code with `(feature NNN)` so the next reader can find the design doc.

The `speckit-*` skills automate steps 2–4 if you want the scaffolding.

## Try it yourself

Pick a small, self-contained feature — [`021-literal-examples`](../specs/021-literal-examples/) is a good one. Read its `spec.md`, then find the code that implements it (grep `feature 021` in `lib/`), then find its integration spec (`spec/integration/feature_021_literal_examples_spec.rb`). Trace the through-line: spec → code → test.

(The later features, 017 onward, ship with just a `spec.md` — the lighter-weight features skip the full `plan.md`/`research.md` set. For a feature that kept the full record, open [`013-resolve-constant-references`](../specs/013-resolve-constant-references/) and read its `research.md`.)

Then in that `research.md`, find one decision where an alternative was considered and rejected. Would you have made the same call? Write down your reasoning. That habit — disagreeing with a recorded decision on paper before touching code — is the whole point of keeping the decisions on paper.
