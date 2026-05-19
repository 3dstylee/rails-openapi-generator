# frozen_string_literal: true

module RailsOpenapiGenerator
  # A normalized parameter ready for the OpenAPI document.
  Parameter = Struct.new(:name, :location, :required, :schema, keyword_init: true)

  # The fully assembled description of one operation.
  Endpoint = Struct.new(
    :http_method, :path, :summary, :description, :parameters, :request_body, :operation_id, :tag,
    keyword_init: true
  )

  # Builds one {Endpoint} from a {Route}, its parsed parameters, and its doc comment.
  class OperationBuilder
    BODY_METHODS = %w[POST PUT PATCH].freeze

    def initialize(schema_mapper: SchemaMapper.new)
      @schema_mapper = schema_mapper
    end

    # Returns an {Endpoint}. `doc_comment`, `param_calls`, and `source_location`
    # are optional so the builder also produces a minimal operation when only
    # the route is known.
    def build(route, doc_comment: nil, param_calls: [], source_location: nil)
      param_calls ||= []
      Endpoint.new(
        http_method: route.http_method,
        path: route.path,
        summary: doc_comment&.summary,
        description: build_description(doc_comment&.description, source_location),
        parameters: build_parameters(route, param_calls),
        request_body: build_request_body(route, param_calls),
        operation_id: operation_id(route),
        tag: route.controller_class_name
      )
    end

    private

    # Combines the YARD description (if any) with a reference to the action's
    # source file and line, so readers can jump straight to the implementation.
    def build_description(text, source_location)
      parts = []
      parts << text if text && !text.empty?
      parts << "_Source: `#{source_location}`_" if source_location
      parts.empty? ? nil : parts.join("\n\n")
    end

    def build_parameters(route, param_calls)
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
      end

      parameters
    end

    def build_request_body(route, param_calls)
      return nil unless body_method?(route)

      body_calls = non_path_calls(route, param_calls)
      return nil if body_calls.empty?

      properties = {}
      required   = []
      body_calls.sort_by(&:name).each do |call|
        properties[call.name] = @schema_mapper.map(call)
        required << call.name if call.required
      end

      schema = { "type" => "object", "properties" => properties }
      schema["required"] = required unless required.empty?
      { "content" => { "application/json" => { "schema" => schema } } }
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
