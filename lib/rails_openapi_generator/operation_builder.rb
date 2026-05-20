# frozen_string_literal: true

module RailsOpenapiGenerator
  # A normalized parameter ready for the OpenAPI document.
  Parameter = Struct.new(:name, :location, :required, :schema, keyword_init: true)

  # The fully assembled description of one operation.
  Endpoint = Struct.new(
    :http_method, :path, :summary, :description, :parameters, :request_body, :operation_id, :tag,
    :response,
    keyword_init: true
  )

  # Builds one {Endpoint} from a {Route}, its parsed parameters, and its doc comment.
  class OperationBuilder
    BODY_METHODS = %w[POST PUT PATCH].freeze

    def initialize(schema_mapper: SchemaMapper.new)
      @schema_mapper = schema_mapper
    end

    # Returns an {Endpoint}. `doc_comment`, `param_calls`, `source_location`,
    # `response`, and `implicit_params` are optional so the builder also
    # produces a minimal operation when only the route is known.
    def build(route, doc_comment: nil, param_calls: [], source_location: nil, response: nil, implicit_params: [])
      param_calls ||= []
      response ||= Response.new(status: 200, undeterminable: true)
      implicit = implicit_param_names(route, param_calls, implicit_params)
      Endpoint.new(
        http_method: route.http_method,
        path: route.path,
        summary: doc_comment&.summary,
        description: build_description(doc_comment&.description, source_location, response),
        parameters: build_parameters(route, param_calls, implicit),
        request_body: build_request_body(route, param_calls, implicit),
        operation_id: operation_id(route),
        tag: route.controller_class_name,
        response: response
      )
    end

    private

    # Combines the YARD description (if any) with a note about an HTML page /
    # file download, and a reference to the action's source file and line.
    def build_description(text, source_location, response)
      parts = []
      parts << text if text && !text.empty?
      parts << page_note(response) if page_note(response)
      parts << "_Source: `#{source_location}`_" if source_location
      parts.empty? ? nil : parts.join("\n\n")
    end

    def page_note(response)
      case response&.kind
      when :html_page
        reference = response.page_reference
        reference ? "_Renders an HTML page (`#{reference}`)._" : "_Renders an HTML page._"
      when :file_download
        "_Sends a file download._"
      when :redirect
        "_Redirects to another URL._"
      end
    end

    # Implicit (`params`-derived) parameter names not already covered by a path
    # segment or a `param!` declaration.
    def implicit_param_names(route, param_calls, implicit_params)
      known = route.path_params + param_calls.filter_map(&:name)
      Array(implicit_params).reject { |name| known.include?(name) }
    end

    def build_parameters(route, param_calls, implicit)
      by_name = param_calls.each_with_object({}) { |call, map| map[call.name] = call if call.name }
      parameters = []

      route.path_params.each do |segment|
        call   = by_name[segment]
        schema = call ? @schema_mapper.map(call) : { "type" => "string" }
        parameters << Parameter.new(name: segment, location: :path, required: true, schema: schema)
      end

      unless body_method?(route)
        non_path_calls(route, param_calls).each do |call|
          parameters << Parameter.new(
            name: call.name, location: :query, required: call.required, schema: @schema_mapper.map(call)
          )
        end
        implicit.each do |name|
          parameters << Parameter.new(name: name, location: :query, required: false, schema: {})
        end
      end

      parameters
    end

    def build_request_body(route, param_calls, implicit)
      return nil unless body_method?(route)

      body_calls = non_path_calls(route, param_calls)
      return nil if body_calls.empty? && implicit.empty?

      properties = {}
      required   = []
      body_calls.sort_by(&:name).each do |call|
        properties[call.name] = @schema_mapper.map(call)
        required << call.name if call.required
      end
      implicit.each { |name| properties[name] ||= {} }

      schema = { "type" => "object", "properties" => sort_properties(properties) }
      schema["required"] = required unless required.empty?
      { "content" => { "application/json" => { "schema" => schema } } }
    end

    def sort_properties(properties)
      properties.sort.to_h
    end

    def non_path_calls(route, param_calls)
      param_calls.reject { |call| call.name.nil? || route.path_params.include?(call.name) }
    end

    def body_method?(route)
      BODY_METHODS.include?(route.http_method)
    end

    # A unique, descriptive operation id derived from the HTTP method and path.
    # Path+method is the OpenAPI uniqueness key, so this never collides — unlike
    # a controller#action id, which repeats when many routes share one action.
    def operation_id(route)
      slug = route.path.gsub(/[^a-zA-Z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
      slug.empty? ? route.http_method.downcase : "#{route.http_method.downcase}_#{slug}"
    end
  end
end
