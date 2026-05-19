# Changelog

All notable changes to this gem are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## [0.4.0] - 2026-05-19

### Added

- File-download detection now resolves **wrapper methods**. An action that
  streams a file through a helper (e.g. `send_file_and_cleanup`) rather than
  calling `send_file`/`send_data` directly is still classified as a file
  download: the generator follows receiverless helper calls to their
  definitions — in the controller, an included concern, or a parent controller
  — recursively through chains of wrappers.
- Resolution is fully static, cycle-guarded, and bounded by a new
  `download_resolution_depth` configuration setting (default 5).

### Changed (additive)

- Some actions previously classified as undeterminable are now classified as
  file downloads. JSON, HTML-page, and direct-download classifications are
  unchanged.

## [0.3.0] - 2026-05-19

### Added

- Endpoints that render an **HTML page** or send a **file download** (rather
  than JSON) are now detected and marked: a non-JSON response content type
  (`text/html` / `application/octet-stream`), a description note, a dedicated
  tag (`HTML Pages` / `File Downloads`), and a vendor extension
  (`x-renders-html` + `x-html-template` / `x-sends-file`).
- The run report counts HTML-page and file-download endpoints.

### Changed (additive)

- Non-JSON endpoints' `responses`, `tags`, and `description` change to reflect
  their classification. JSON-endpoint output is unchanged — a `render json:`
  always takes precedence over an HTML view. Regenerate to pick up the marks.

## [0.2.1] - 2026-05-19

### Fixed

- When an action has multiple `render json:` calls, the response body is now
  taken from the happy-path render. Renders carrying an explicit error status
  (4xx/5xx) are skipped, so an early `render status: :bad_request, json: …`
  guard no longer masquerades as the success response.
- A response field whose value is not a literal (e.g. `json: { ids: some_var }`)
  is now documented with a permissive `{}` ("any") schema. It was previously
  mistyped as `"string"` because the internal unresolved-value sentinel is a
  Ruby Symbol.

## [0.2.0] - 2026-05-19

### Added

- Each operation's success response now carries a **response body schema**,
  derived statically from the action's jbuilder view template
  (`.json.jbuilder`) or a literal `render json:` call.
- Success responses are filed under a conventional status code: `200` for
  reads/updates, `201` for creation, `204` for deletion / `head :no_content`.
- Endpoints whose response shape cannot be determined are reported as warnings
  and still produce a valid (body-less) success response.

### Changed (breaking output change)

- The generated document's `responses` object changed for every operation:
  previously a fixed `{ "200": { "description": "Successful response" } }`
  placeholder, now a real status code with a `content`/`schema` body where one
  could be determined.

  **Migration**: regenerate the document (`rake openapi:generate`) and review
  the diff. Consumers and tooling that relied on the old placeholder `200`
  entry should expect `201`/`204` for creation/deletion operations and a
  populated response schema elsewhere. No configuration or API change is
  required — the new behavior is automatic.

## [0.1.0]

### Added

- Initial release: generate an OpenAPI 3.1 document from Rails routes,
  `rails_param` request validations, and YARD comments, via a rake task or CLI.
- Operations tagged by controller class; descriptions link to the action's
  source file and line.
