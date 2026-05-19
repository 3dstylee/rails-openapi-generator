# frozen_string_literal: true

module RailsOpenapiGenerator
  # Assembles an operation's success {Response} from a {Classification}: the
  # status code, the kind, and (for JSON) the body schema.
  class ResponseBuilder
    STATUS_BY_METHOD = { "GET" => 200, "PUT" => 200, "PATCH" => 200, "POST" => 201, "DELETE" => 204 }.freeze
    DEFAULT_STATUS = 200

    # `classification` is a {Classification}; `view_schema` is the parsed
    # jbuilder schema Hash for a JSON endpoint resolved via a view, or nil.
    def build(route, classification:, view_schema: nil)
      render_result = classification.render_result
      return Response.new(status: 204) if no_content?(route, render_result)

      case classification.kind
      when :html_page
        Response.new(status: status_for(route), kind: :html_page, page_reference: classification.template_name)
      when :file_download
        Response.new(status: status_for(route), kind: :file_download)
      when :json
        json_response(route, render_result, view_schema)
      else
        Response.new(status: status_for(route), undeterminable: true)
      end
    end

    private

    def json_response(route, render_result, view_schema)
      # A literal `render json:` takes precedence over the jbuilder view.
      body = render_result.renders_json ? render_result.schema : view_schema

      if body.nil?
        Response.new(status: status_for(route), undeterminable: true)
      else
        Response.new(status: status_for(route), body: body)
      end
    end

    def no_content?(route, render_result)
      render_result.no_content? || route.http_method == "DELETE"
    end

    def status_for(route)
      STATUS_BY_METHOD.fetch(route.http_method, DEFAULT_STATUS)
    end
  end
end
