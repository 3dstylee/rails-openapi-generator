# Phase 0 Research: Explicit Success Status Codes

## R1. Extracting status signals from an action

**Decision**: Read two kinds of status signal from the action's Ripper AST:

- the `status:` option of every `render` call — `RenderExtractor#collect_renders`
  already evaluates each `render`'s option hash, including `status:`;
- the argument of every `head` call — `RenderExtractor` already locates `head`
  calls via `render_calls(node, "head")`.

**Rationale**: Both signal sources are already partially read by
`RenderExtractor` (render `status:` for the happy/error render classification;
`head` for the current `no_content` check). The feature consolidates and
generalizes that existing work rather than adding a new scanner.

## R2. Mapping status symbols to codes

**Decision**: Reuse `RenderExtractor::STATUS_CODES` — the existing Rails
status-symbol → numeric-code table. Extend it if any common 2xx/3xx symbol is
missing (e.g. `:see_other`, `:not_modified`, `:moved_permanently`). An integer
status is used directly. A symbol with no table entry maps to nil.

**Rationale**: The table already exists for happy/error render classification;
one table, one source of truth (Constitution I).

## R3. Choosing the explicit status

**Decision**: Collect the resolved code of every status signal (render
`status:` and `head` argument); keep only happy-path codes (200–399); the
**last** one in source order is the action's explicit success status. If no
happy-path signal exists, the explicit status is nil.

**Rationale**: Satisfies FR-004 (error statuses ignored) and FR-005 (last wins).
"Last wins" matches how the happy-path `render json:` is already chosen
(feature 002), so early error-guard statements never shadow the real success
path.

## R4. The `head` body rule

**Decision**: `RenderResult` carries a `head` boolean — true when the action has
a happy-path `head` call. `ResponseBuilder` documents no response body when
`head` is true (or the status is 204). A `head` response is body-less by
definition.

**Rationale**: Satisfies FR-008. Keeping it a flag on `RenderResult` (rather
than changing the classified `kind`) honors FR-010 — the kind is unaffected,
only the body is omitted.

## R5. Fallback to the HTTP-method convention

**Decision**: When `RenderResult.explicit_status` is nil, `ResponseBuilder`
keeps the existing method-based mapping — `GET`/`PUT`/`PATCH` → 200, `POST` →
201, `DELETE` → 204.

**Rationale**: Satisfies FR-007; most actions set no explicit status, so the
convention must remain the default (backward compatibility).

## R6. Replacing `no_content` with `explicit_status` + `head`

**Decision**: `RenderResult`'s current `no_content` boolean is removed; its job
is taken over by `explicit_status` (`head :no_content` → `204`) and `head`
(body absence). `ResponseBuilder`'s `no_content?` special case is removed in
favor of: status = explicit-or-method; body omitted when `head` or status 204.

**Rationale**: `no_content` was a one-off for a single `head` form. The general
`explicit_status` covers `head :no_content` as just another value and removes a
special case (Constitution I — fewer branches).

## R7. Scope boundary

**Decision**: The feature changes only the documented **status code** and the
**body absence for `head`**. The response **kind** (JSON / HTML page / file
download / undeterminable) and all other marks (tags, vendor extensions,
description note, parameters) are computed exactly as before.

**Rationale**: Satisfies FR-010 — a focused, low-risk change verified by a
regression test.

## Resolved unknowns

All Technical Context items are resolved. No new dependency, class, file, or
configuration. No `NEEDS CLARIFICATION` markers — the feature description fully
specified the behavior.
