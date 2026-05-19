# frozen_string_literal: true

module RailsOpenapiGenerator
  # Assembles an operation's success {Response} from a {Classification}: the
  # status code, the kind, and (for JSON) the body schema.
  #
  # The status code is the explicit status the action sets (`head` /
  # `render status:`) when present, and otherwise the HTTP-method convention.
  class ResponseBuilder
    STATUS_BY_METHOD = { "GET" => 200, "PUT" => 200, "PATCH" => 200, "POST" => 201, "DELETE" => 204 }.freeze
    DEFAULT_STATUS = 200

    # `classification` is a {Classification}; `view_schema` is the parsed
    # jbuilder schema Hash for a JSON endpoint resolved via a view, or nil.
    def build(route, classification:, view_schema: nil)
      render_result = classification.render_result
      status = status_for(route, render_result)
      # A 204 or a `head` response is a determinate, body-less response.
      empty = status == 204 || render_result.head?

      case classification.kind
      when :html_page
        Response.new(status: status, kind: :html_page, page_reference: classification.template_name)
      when :file_download
        Response.new(status: status, kind: :file_download)
      when :json
        json_response(status, render_result, view_schema, empty)
      else
        Response.new(status: status, undeterminable: !empty)
      end
    end

    private

    # The explicit status the action sets, falling back to the HTTP-method
    # convention when the action sets none.
    def status_for(route, render_result)
      render_result.explicit_status || STATUS_BY_METHOD.fetch(route.http_method, DEFAULT_STATUS)
    end

    def json_response(status, render_result, view_schema, empty)
      return Response.new(status: status) if empty

      # A literal `render json:` takes precedence over the jbuilder view.
      body = render_result.renders_json ? render_result.schema : view_schema

      if body.nil?
        Response.new(status: status, undeterminable: true)
      else
        Response.new(status: status, body: body)
      end
    end
  end
end
