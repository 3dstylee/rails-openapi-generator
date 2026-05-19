# Phase 0 Research: Happy-Path Response Bodies

## R1. Mapping an action to its jbuilder view template

**Decision**: Resolve the template by Rails view-path convention —
`<rails_root>/app/views/<controller_path>/<action>.json.jbuilder` — and also
honor an explicit `render` in the action body that names a template
(`render :other_action`, `render template: "path"`, `render "path"`) when the
argument is a literal.

**Rationale**: The convention covers the overwhelming majority of Rails actions
(implicit rendering). `controller_path` is already known from the route
(`api/users`), so the lookup is a deterministic file-existence check — no code
execution (FR-008). Explicit literal `render` of another template is a small,
common deviation worth following.

**Alternatives considered**:
- *Asking Rails for the resolved view path at runtime*: rejected — requires a
  request/controller context, i.e. execution.
- *Only the convention, ignoring explicit `render`*: rejected — would document
  the wrong shape for actions that render a different template.

**Limitation**: Templates resolved through non-literal arguments, or served by
mounted engines with custom view paths, are not located → undeterminable
response (FR-007).

## R2. Parsing jbuilder templates statically

**Decision**: Parse each `.json.jbuilder` file with stdlib `Ripper` and walk the
AST for `json.*` calls, building a response schema. Supported constructs:

| jbuilder construct | Schema result |
|--------------------|---------------|
| `json.name value` | property `name` (permissive type — see R3) |
| `json.name do … end` | property `name` as a nested object |
| `json.array! collection do …` | root/property becomes an array of objects |
| `json.array! collection, partial:, as:` | array of the partial's object |
| `json.partial! "path"` / `json.partial! "path", …` | inline the partial's schema |
| `json.extract! obj, :a, :b` | properties `a`, `b` |
| `json.set! :key, value` | property `key` |
| `json.key_format!` / `json.merge! …` | best-effort; unknown parts ignored |
| `if` / `unless` around `json.*` | the guarded properties are included (union of branches) |

**Rationale**: jbuilder has no static metadata; the template *is* the contract.
Ripper is stdlib (no new dependency, Constitution I) and deterministic. Treating
conditionals as a union keeps the documented shape a superset — better for a
consumer than dropping fields. `json.partial!` is followed because partials are
how jbuilder apps share resource shapes.

**Alternatives considered**:
- *Rendering the template with jbuilder against a stub object*: rejected —
  execution, and needs realistic data.
- *Regex scraping*: rejected — fragile on blocks/partials/multiline calls.

**Limitation (FR-013)**: dynamic keys (`json.set!(computed)`), values behind
method calls, and unlocatable partials cannot be fully resolved → the property
is emitted permissively or that fragment is skipped; the run never aborts.

## R3. Field type inference

**Decision**: Field **names and nesting** are always recovered. Field **types**
are best-effort:

- From a **literal `render json:`** value → typed precisely (a string literal →
  `string`, integer → `integer`, nested hash → `object`, array → `array`) via
  the shared `LiteralEvaluator`.
- From a **jbuilder value expression** (`json.id @user.id`) → emitted as a
  permissive schema (`{}`, no `type`) because the value's type is not knowable
  without resolving the receiver's class.
- `json.array!` / `json.* do … end` / nested hashes → `type: array` / `object`
  structurally, regardless of leaf types.

**Rationale**: The primary value of a response body is *what fields come back
and how they nest* — that is fully recoverable. Leaf types are a refinement; the
spec (FR-013, Assumptions) explicitly permits permissive typing. An empty schema
`{}` is valid OpenAPI 3.1 and means "any".

**Alternatives considered**:
- *ActiveRecord column introspection* (resolve `@user` → `User`, read DB column
  types): rejected for this feature — requires statically resolving each
  instance variable's class, a substantial sub-project. Recorded as a future
  enhancement.
- *Runtime capture of a real response*: rejected — execution (FR-008).

## R4. Literal `render json:` extraction and precedence

**Decision**: Walk the action's Ripper AST for `render` calls carrying a `json:`
key. If the value is a literal (hash/array/scalar), convert it to a schema with
the shared `LiteralEvaluator`. A literal `render json:` in the action body
**takes precedence** over a jbuilder template for the same action.

**Rationale**: An action that contains `render json: { … }` returns exactly
that; the literal is the most direct evidence of the response. Many `spacely_web`
actions use this for simple acknowledgements (`render json: { result: :success }`).

**Limitation (FR-014)**: a `render json:` whose argument is a variable, method
call, or serializer instance is **not** guessed; if no jbuilder template applies
either, the operation falls back to FR-007.

## R5. Success status code

**Decision**: File the success response by HTTP method — `GET`/`PUT`/`PATCH` →
`200`, `POST` → `201`, `DELETE` → `204`. A `204` response carries no body
schema. If an action's source shows an explicit `head :no_content` / `head 204`
with no body, treat it as `204`.

**Rationale**: Matches Rails REST conventions and satisfies FR-005. Deriving the
exact code per action without execution is not generally possible; the
method-based mapping is the conventional, deterministic choice.

**Alternatives considered**:
- *Always 200*: rejected — inaccurate for creation and deletion (FR-005).
- *Parsing every `render status:` in the action*: deferred — only the
  unambiguous `head`/no-content case is read statically.

## R6. Collection vs. member responses

**Decision**: A template whose root call is `json.array!` → the response body is
an `array`; a literal `render json:` of an `Array` → `array`; otherwise an
`object`. The array's `items` is the element object schema (from the partial or
inline block).

**Rationale**: Satisfies FR-003 and the collection/member edge case directly
from a structural signal in the source.

## R7. Shared `LiteralEvaluator`

**Decision**: Extract the Ripper-literal-to-Ruby-value logic currently embedded
in `ParamExtractor` into a standalone `LiteralEvaluator` module. `ParamExtractor`
and the new `RenderExtractor` both depend on it.

**Rationale**: `RenderExtractor` needs exactly the literal-evaluation `ParamExtractor`
already implements (scalars, strings, symbols, arrays, hashes, ranges, regexps,
`true`/`false`/`nil`). Duplicating it would violate Constitution I; extraction
removes the duplication and gives both call sites one tested implementation.

## Resolved unknowns

All Technical Context items are resolved. No new runtime dependency is
introduced (R2 uses stdlib Ripper). No `NEEDS CLARIFICATION` markers remain —
the spec's open item (response source) was settled during `/speckit-specify`
as jbuilder templates + literal `render json:`.
