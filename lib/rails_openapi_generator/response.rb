# frozen_string_literal: true

module RailsOpenapiGenerator
  # One status entry of an operation's response set: a status code, an
  # optional body schema, and (feature 012) an optional multi-content-type
  # map. The body is nil for a body-less entry (head, no-known-body, or
  # non-JSON kind). It may be an `{"oneOf": [...]}` schema for a
  # multi-shape union (feature 010 FR-004). `content_types`, when set,
  # supersedes `body` at emission time: each key is an OpenAPI content
  # type string (e.g. `"application/json"`, `"text/html"`); each value is
  # the schema for that content type, or nil for a known-but-schema-less
  # type (today's `text/html` placeholder).
  ResponseEntry = Struct.new(:status, :body, :content_types, keyword_init: true)

  # The success response of one operation, as an ordered list of status
  # entries (`entries`). A single-status operation has a one-element list
  # and emits byte-identically to pre-`0.9.0` output. A multi-status JSON
  # operation has one entry per unique status the action can produce.
  #
  # `kind` is `:json`, `:html_page`, `:file_download`, or `:redirect`.
  # `undeterminable` (meaningful only for `:json`) marks the fallback case
  # where no render site contributes — the entry list still has one entry
  # under the HTTP-method convention, but the body is unknown.
  # `page_reference` carries the HTML template name for an `:html_page`.
  # `entries` deliberately shadows `Struct#entries` (an alias of `to_a`);
  # the Struct method is unused on this type, and renaming would obscure
  # the intent of the field.
  Response = Struct.new(
    :entries, # rubocop:disable Lint/StructNewOverride
    :description, :undeterminable, :kind, :page_reference,
    keyword_init: true
  ) do
    def initialize(entries: nil, status: nil, body: nil,
                   description: "Successful response",
                   undeterminable: false, kind: :json, page_reference: nil)
      entries ||= [ResponseEntry.new(status: status, body: body)]
      super(entries: entries, description: description,
            undeterminable: undeterminable, kind: kind, page_reference: page_reference)
    end

    # Convenience accessor — the first (and, for single-entry kinds, only)
    # entry's status. Multi-status JSON callers should iterate `entries`.
    def status
      entries.first&.status
    end

    def body
      entries.first&.body
    end

    def undeterminable?
      undeterminable
    end

    def body?
      !body.nil?
    end

    def html_page?
      kind == :html_page
    end

    def file_download?
      kind == :file_download
    end

    def redirect?
      kind == :redirect
    end
  end
end
