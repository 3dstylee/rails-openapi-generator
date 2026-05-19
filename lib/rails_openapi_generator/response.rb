# frozen_string_literal: true

module RailsOpenapiGenerator
  # The success ("happy path") response of one operation: a status code, an
  # optional body schema, a description, and a kind.
  #
  # `kind` is `:json`, `:html_page`, or `:file_download`. `body` is an OpenAPI
  # schema Hash, or nil for a 204 / no-content response, a non-JSON response,
  # and an undeterminable JSON response. `undeterminable` (meaningful only for
  # `:json`) marks a JSON response whose shape could not be determined.
  # `page_reference` carries the HTML template name for an `:html_page`.
  Response = Struct.new(
    :status, :body, :description, :undeterminable, :kind, :page_reference,
    keyword_init: true
  ) do
    def initialize(status:, body: nil, description: "Successful response",
                   undeterminable: false, kind: :json, page_reference: nil)
      super
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
  end
end
