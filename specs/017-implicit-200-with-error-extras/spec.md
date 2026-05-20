# Feature 017: Implicit happy-path entry when only error extras are present

**Status**: ready to implement
**Created**: 2026-05-20
**Constitution**: V (versioned backward-compatible output) — bump `0.16.0` → `0.17.0`

## Problem

A controller action with **no** explicit response signal (no `render`, no
`head`, no `redirect_to`, no resolvable view template) AND a `rescue_from`
declared on the controller class (or inherited from a base controller) loses
its implicit happy-path response entry in the generated OpenAPI document.

Concrete repro (from the user's `spacely_web`):

```ruby
class ProjectPanelsController < BaseController
  rescue_from ProjectPanels::UpsertService::ProjectPanelNotFoundError,
              with: :handle_project_panel_not_found

  def upload_manually_edited_image
    permitted_params = params.permit(:scene_id, :switch_id, :image)
    panel = panel_from_request(permitted_params)
    ProjectPanelForm.new(@project).upload_manually_edited_image(panel, permitted_params[:image])
    BatchJob.build_upload_panorama_task(@project, panel).perform_later(wait: 3)
  end
end
```

No `app/views/.../upload_manually_edited_image.json.jbuilder` exists. Rails'
implicit response at runtime is a body-less 200. The generator's current
output for this operation is **only** the 404 entry contributed by
`rescue_from` — no 200 entry at all.

## Root cause

`ResponseBuilder#undeterminable_response`
([response_builder.rb:113–128](../../lib/rails_openapi_generator/response_builder.rb#L113-L128))
short-circuits to a body-less convention-status response **only when
`sites.empty?`**. With `rescue_from` extras populating `sites`, the gate
opens to `entries_from_sites(sites, route)` — which builds entries strictly
from the rescue handlers' explicit statuses (e.g. 404, 422), with no
synthetic entry for the action's own implicit 200.

Feature 014 introduced the rescue_from extras. Feature 015 introduced the
no-signal body-less 200 fallback. Their interaction left this gap:
"some-signal-but-only-error-signals" actions.

## User Stories

### US1 (P1) — Body-less happy-path entry alongside error extras

**Given** an action with no explicit happy-path signal (no inline render, no
head, no redirect, no view template) and at least one error-status entry
contributed by extras (`rescue_from`, `before_action`, helper renders),
**when** the generator builds the operation, **then** the response set must
include a body-less entry at the HTTP-method convention status (200 for
GET/PUT/PATCH, 201 for POST, 204 for DELETE) in addition to the
error-status entries.

**Independent test**: fixture controller inheriting from
`ErrorRescuingController` with one action containing no render/head/redirect
and no view file. Assert the operation's `responses` contains both the
convention status (body-less) AND the rescue-from statuses.

## Functional Requirements

- **FR-001**: When `undeterminable_response` runs with non-empty `sites` and
  the action source contributes no render site (i.e.
  `render_result.render_sites.empty?`), the response set MUST include a
  body-less entry at `status_for(route, render_result)`.
- **FR-002**: When an entry at the convention status already exists (e.g.
  contributed by a helper or before_action), the new logic MUST NOT
  duplicate or overwrite it.
- **FR-003**: When the action source DOES contribute a render site (even
  body-less, e.g. `head :ok` or a template render with no resolvable view),
  the new logic MUST NOT fire — the existing site already represents the
  happy path.
- **FR-004**: Entries must remain sorted by ascending status code (existing
  invariant preserved).
- **FR-005**: Operations whose action source contributes any render site
  emit byte-identical responses to `0.16.0`. The new code path fires only
  in the specific "no action signal + non-empty extras" case.

## Out of scope

- Heuristics for "should the implicit 200 carry a body" — the body is
  always `nil` (matches Rails' implicit empty response and feature 015's
  posture). Static signals to infer a body would require parsing the
  helper/before_action chain for a happy render, which is a larger
  exploration left for a future feature.
- Changing the response status convention table (`STATUS_BY_METHOD`).

## Success Criteria

- **SC-001**: The motivating fixture (an action with `rescue_from` only and
  no own happy signal) documents both the convention status AND the
  rescue's status.
- **SC-002**: All existing operations with at least one action-source render
  site emit byte-identical responses to `0.16.0` (regression coverage).
- **SC-003**: Two consecutive runs of the generator produce byte-identical
  output for the affected operations (determinism).
