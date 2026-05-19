# Feature Specification: Nested Parameter Blocks

**Feature Branch**: `008-nested-param-blocks`

**Created**: 2026-05-19

**Status**: Draft

**Input**: User description: "Support nested rails_param param! blocks. When a param! of type Hash or Array is given a block, descend into it: a Hash param!'s block contains <blockvar>.param! :name, Type calls that become the object's nested properties; an Array param!'s block contains <blockvar>.param! index, Type calls that declare the array's items schema. Nesting is recursive (a nested param! may itself have a block) and bounded against runaway depth. The block variable is the param!'s own block parameter; calls on it are recognized even though they have an explicit receiver. Type and constraints of nested params map the same way flat param! constraints do today."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Object parameters expose their nested properties (Priority: P1)

An API author declares a structured request parameter with `rails_param` by giving a
`param!` of type `Hash` a block, and inside that block calls `param!` on the block
variable for each field of the object (`q.param! :keyword, String`). Today the
generated document shows the parameter only as a bare object with no fields. The
author wants the document to describe each declared field so consumers see the real
shape of the object.

**Why this priority**: Object parameters with declared sub-fields are the most common
nested shape and the case the user reported (`param! :q, Hash do |q| q.param! :keyword, String ... end`). Without this the document understates the API contract — it is the MVP.

**Independent Test**: Add a controller action whose `param!` of type `Hash` has a
block declaring two scalar fields, generate the document, and confirm the parameter's
schema is an object whose `properties` contains both fields with their mapped types
and constraints.

**Acceptance Scenarios**:

1. **Given** a `param!` of type `Hash` with a block declaring `q.param! :keyword, String` and `q.param! :page, Integer`, **When** the document is generated, **Then** that parameter's schema is an object whose `properties` has a `keyword` (string) and a `page` (integer) entry.
2. **Given** a nested `param!` declared with constraints (e.g. `required: true`, `in:`), **When** the document is generated, **Then** the nested property carries the same constraint mapping a flat top-level `param!` would produce today.
3. **Given** a `param!` of type `Hash` whose block declares no nested `param!` calls, **When** the document is generated, **Then** the parameter remains a bare object schema (unchanged from today).

---

### User Story 2 - Array parameters describe their item shape (Priority: P2)

An API author declares an array request parameter by giving a `param!` of type
`Array` a block, and inside that block calls `param!` on the block variable with the
array-index block parameter to declare the type of the array's elements
(`array.param! index, String`). The author wants the generated document's array
schema to describe what each item looks like via its `items` schema.

**Why this priority**: Array element typing builds on the same descent mechanism as
US1 but covers a less common shape; it is valuable but secondary to object fields.

**Independent Test**: Add a controller action whose `param!` of type `Array` has a
block declaring an indexed element `param!`, generate the document, and confirm the
array parameter's schema has an `items` schema of the declared element type.

**Acceptance Scenarios**:

1. **Given** a `param!` of type `Array` with a block declaring `array.param! index, String`, **When** the document is generated, **Then** that parameter's schema is an array whose `items` schema is of type string.
2. **Given** an `Array` `param!` whose element is itself a `Hash` with a block, **When** the document is generated, **Then** the array's `items` schema is an object whose `properties` reflect the nested declarations.
3. **Given** a `param!` of type `Array` whose block declares no element `param!`, **When** the document is generated, **Then** the parameter remains a bare array schema (unchanged from today).

---

### User Story 3 - Deep nesting is followed and bounded (Priority: P3)

An API author nests structured parameters several levels deep — an object field that
is itself an object with its own fields, or an array of objects. The author wants
every level described, while the generator stays safe against pathological or cyclic
declarations by stopping the descent at a bounded depth.

**Why this priority**: Recursion correctness and the safety bound matter for
robustness, but most real declarations are one or two levels deep, so this refines
US1/US2 rather than standing alone.

**Independent Test**: Add a controller action with a `param!` nested three or more
levels deep, generate the document, and confirm every level is described; then
confirm a declaration deeper than the bound is truncated without error.

**Acceptance Scenarios**:

1. **Given** a `param!` of type `Hash` whose block declares a nested `Hash` field that itself has a block declaring scalar fields, **When** the document is generated, **Then** all three levels appear in the nested schema.
2. **Given** a nested declaration deeper than the configured depth bound, **When** the document is generated, **Then** the descent stops at the bound, the run still completes successfully, and the over-depth portion is left as a bare object/array schema.

---

### Edge Cases

- A `param!` of type `Hash` or `Array` **without** a block keeps today's behavior — a bare object/array schema.
- A block on a `param!` whose type is neither `Hash` nor `Array` (e.g. `String`) is ignored; the parameter maps as it does today.
- A nested `param!` call inside a block on a receiver that is **not** the block variable (e.g. `params.param!` or an unrelated object) is not treated as a nested property.
- A nested `param!` whose type or value cannot be determined maps to the same permissive ("any") schema a flat unresolved `param!` produces today.
- A nested `param!` named the same as an already-declared sibling: the last declaration wins (consistent with how repeated declarations behave).
- An empty block, or a block containing only non-`param!` statements, yields a bare object/array schema.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The generator MUST, when a `param!` of type `Hash` has a block, descend into the block and collect each `param!` call made on the block's own block variable as a nested property of that object.
- **FR-002**: The generator MUST, when a `param!` of type `Array` has a block, descend into the block and use a `param!` call made on the block's own block variable (with the array-index block parameter as its name argument) to declare the array's element (items) schema.
- **FR-003**: Each nested `param!`'s type and constraints MUST map to a schema using the same rules already applied to flat top-level `param!` declarations.
- **FR-004**: Descent MUST be recursive — a nested `param!` that is itself of type `Hash`/`Array` with a block MUST have its own block descended into.
- **FR-005**: Recursive descent MUST be bounded by a maximum nesting depth so a pathological or cyclic declaration cannot cause runaway processing; reaching the bound MUST stop the descent for that branch without aborting the run.
- **FR-006**: A `param!` call MUST be recognized as a nested declaration only when its receiver is the enclosing `param!`'s block variable; a `param!` with any other receiver, or none, inside the block MUST NOT be treated as a nested property of that object/array.
- **FR-007**: A `param!` of type `Hash`/`Array` with no block, or with a block that declares no qualifying nested `param!` calls, MUST continue to produce the same bare object/array schema it produces today.
- **FR-008**: A block attached to a `param!` whose type is neither `Hash` nor `Array` MUST be ignored.
- **FR-009**: With no nested `param!` blocks present anywhere, the generated document MUST be byte-identical to what is produced today (the feature is purely additive).

### Key Entities *(include if feature involves data)*

- **Nested parameter declaration**: A `param!` call appearing inside another `param!`'s block, invoked on that block's variable. Carries a name (or array index), a type, and constraints — the same attributes a top-level `param!` carries.
- **Parameter schema tree**: The recursive schema produced for a structured parameter — an object node with named property children, or an array node with a single item-schema child, where each child may itself be such a node.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A `Hash` `param!` whose block declares N scalar fields produces an object schema whose `properties` contains exactly those N fields with correct types — verified for the user's reported example.
- **SC-002**: An `Array` `param!` whose block declares an indexed element produces an array schema with a populated `items` schema of the declared type.
- **SC-003**: A declaration nested at least three levels deep is fully described at every level in the generated document.
- **SC-004**: A declaration nested beyond the depth bound completes generation with no error and a valid OpenAPI 3.1 document.
- **SC-005**: For an application with no nested `param!` blocks, the generated document is unchanged from the prior version.

## Assumptions

- The depth bound reuses the existing `method_resolution_depth` configuration setting rather than introducing a new setting, keeping the configuration surface small (Constitution Principle I).
- Nested object properties are not marked `required` at the object level beyond the per-property constraint mapping already applied to flat `param!` declarations; an OpenAPI object-level `required` array is out of scope for this feature.
- The block variable is identified by the literal parameter name in the block's parameter list; shadowing or reassignment of that variable inside the block is not analyzed (consistent with the static-analysis approach used elsewhere in the gem).
- Nested parameters are documented within the schema of their containing parameter; they do not become separate top-level parameters.
- This feature extends the existing `rails_param` parameter extraction (feature 001) and its schema mapping; it does not change response-body handling.
