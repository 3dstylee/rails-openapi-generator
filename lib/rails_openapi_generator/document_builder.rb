# frozen_string_literal: true

module RailsOpenapiGenerator
  # Assembles a complete OpenAPI 3.1 document Hash from a set of {Endpoint}s.
  class DocumentBuilder
    OPENAPI_VERSION = "3.1.0"
    METHOD_ORDER    = %w[get post put patch delete].freeze
    LOCATION_ORDER  = { path: 0, query: 1, body: 2 }.freeze

    def initialize(configuration)
      @configuration = configuration
    end

    # Returns the OpenAPI document Hash with deterministically ordered contents.
    def build(endpoints)
      document = {
        "openapi" => OPENAPI_VERSION,
        "info" => info
      }
      tags = tags(endpoints)
      document["tags"] = tags unless tags.empty?
      document["paths"] = paths(endpoints)
      document
    end

    private

    # One OpenAPI tag per controller, so viewers group operations by controller.
    def tags(endpoints)
      endpoints.filter_map(&:tag).uniq.sort.map { |name| { "name" => name } }
    end

    def info
      {
        "title" => @configuration.title || default_title,
        "version" => @configuration.api_version
      }
    end

    def default_title
      return "API" unless defined?(Rails) && Rails.respond_to?(:application) && Rails.application

      Rails.application.class.name.to_s.split("::").first || "API"
    rescue StandardError
      "API"
    end

    def paths(endpoints)
      grouped = Hash.new { |hash, key| hash[key] = {} }

      endpoints.sort_by { |endpoint| [endpoint.path, endpoint.http_method] }.each do |endpoint|
        grouped[openapi_path(endpoint.path)][endpoint.http_method.downcase] = operation(endpoint)
      end

      grouped.keys.sort.to_h do |path|
        [path, sort_by_method(grouped[path])]
      end
    end

    # Converts Rails `:id` / `*splat` segments to OpenAPI `{id}` syntax.
    def openapi_path(path)
      path.gsub(/[:*]([A-Za-z_][A-Za-z0-9_]*)/) { "{#{Regexp.last_match(1)}}" }
    end

    def sort_by_method(operations)
      operations.keys.sort_by { |method| METHOD_ORDER.index(method) || METHOD_ORDER.size }
                     .to_h { |method| [method, operations[method]] }
    end

    def operation(endpoint)
      result = { "operationId" => endpoint.operation_id }
      result["tags"]        = [endpoint.tag] if endpoint.tag
      result["summary"]     = endpoint.summary if endpoint.summary
      result["description"] = endpoint.description if endpoint.description

      parameters = endpoint.parameters.reject { |param| param.location == :body }
      result["parameters"]  = sorted_parameters(parameters) unless parameters.empty?
      result["requestBody"] = endpoint.request_body if endpoint.request_body
      result["responses"]   = { "200" => { "description" => "Successful response" } }
      result
    end

    def sorted_parameters(parameters)
      parameters
        .sort_by { |param| [LOCATION_ORDER.fetch(param.location, 9), param.name] }
        .map do |param|
          {
            "name" => param.name,
            "in" => param.location.to_s,
            "required" => param.required,
            "schema" => param.schema
          }
        end
    end
  end
end
