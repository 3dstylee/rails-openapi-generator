# Reading rails-openapi-generator

A walkthrough of [`rails-openapi-generator`](../README.md) for an engineer who knows Ruby (or any language with a comparable feature set) and has touched a Rails app once or twice, but has never built a documentation generator or a static analyzer.

## What this gem does, in one sentence

It walks a Rails application's routes and source files and produces a single OpenAPI 3.1 document describing every endpoint — without running any of the controller code.

That sentence hides almost every interesting decision in this codebase. The book exists to unpack it.

## Why a book and not a README

The [README](../README.md) tells you *what* to type. It does not tell you why we built the gem this way. The shape of every file in `lib/rails_openapi_generator/` is a response to a real constraint we hit: a tradeoff we made, a Rails behavior we had to model, a class of user code we couldn't reach with our first attempt. The book is the conversation behind those decisions.

We chose static analysis. We chose to lean on Ripper rather than `parser`. We chose to never raise from the parser. We chose to emit byte-identical output across runs. Each of these closes one door and opens another. The chapters walk that ground in the order it makes sense — not the order the code happens to load.

## How to read this

Read with `lib/rails_openapi_generator/` open in another pane. Every chapter quotes real source and links to the file. The quotes are current as of version [`0.24.0`](../lib/rails_openapi_generator/version.rb) — if a quote drifts from the source, trust the source.

The chapters build on each other. Skipping ahead is fine if you already know a topic, but the data-model chapter (4) is load-bearing — almost every later chapter assumes those struct names. If a chapter cites a struct or a sentinel you haven't seen, it's defined in chapter 4 or chapter 2.

You'll see two voices:

- **First-person plural** ("we decided…") for designed tradeoffs — choices that have alternatives.
- **Second-person** ("you should…") for pure mechanics — facts about how Ripper or Rails works.

Every chapter ends with a **Try it yourself** exercise. They're small. Do them. Reading is not enough; the only way to learn a code path is to perturb it.

You'll also see **Aside** sidebars. They're side-quests — interesting context that's safe to skip on first pass.

## Table of contents

1. [Anatomy of the repo](01-anatomy.md) — where the code lives and what each top-level directory is for.
2. [Why static analysis](02-static-analysis.md) — the central design choice and what it costs.
3. [The output contract](03-output-contract.md) — what we promise to emit and why it's byte-identical across runs.
4. [The data model](04-data-model.md) — the small set of structs that flow between stages.
5. [The pipeline](05-pipeline.md) — how `Generator` orchestrates one route into one operation.
6. [Parameters from `param!`](06-parameters.md) — turning a Ruby DSL into OpenAPI parameter and request-body schemas.
7. [Response bodies](07-responses.md) — the hardest part of the gem: four sources, multi-status, unions, partials.
8. [Following the code](08-following-code.md) — how we statically chase a helper, a callback, or a rescue handler.
9. [Wiring it to Rails](09-wiring.md) — CLI, rake task, railtie, configuration.
10. [Operational concerns](10-operations.md) — the report, the writer, resilience under bad input.
11. [Tests](11-tests.md) — the dummy Rails app and what each test layer is for.
12. [Spec-driven development](12-process.md) — how the `specs/` directory shapes work.
13. [Where to go next](13-where-next.md) — open gaps and good first contributions.

## Prerequisites

- Comfortable Ruby. You don't need to be an expert — but blocks, structs, modules, and `respond_to?` should feel natural.
- A working mental model of a Rails request: route → controller action → render. You don't need to have built a gem before.
- Comfortable reading a moderately tangled AST. We use [Ripper](https://docs.ruby-lang.org/en/master/Ripper.html), Ruby's bundled parser. Chapter 2 reintroduces it; you don't need prior exposure.

Nothing else. You will not need to know OpenAPI 3.1 in detail — chapter 3 covers the slice we emit. You will not need to know YARD — chapter 6 covers the slice we read.

## A style note

The code in `lib/` does not over-comment. When you see a comment, it usually marks the *why*, not the *what*. We write code under the same rule the book follows: a clear sentence over a clear paragraph, real reasons over plausible-sounding ones, no apologetic notes for absent features. If a comment in the code feels load-bearing, it is — read it twice.

Now turn to chapter 1.
