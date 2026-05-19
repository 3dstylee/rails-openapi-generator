# frozen_string_literal: true

require_relative "rails_openapi_generator/version"
require_relative "rails_openapi_generator/errors"
require_relative "rails_openapi_generator/configuration"
require_relative "rails_openapi_generator/route"
require_relative "rails_openapi_generator/report"
require_relative "rails_openapi_generator/route_collector"
require_relative "rails_openapi_generator/source_locator"
require_relative "rails_openapi_generator/yard_parser"
require_relative "rails_openapi_generator/doc_comment_extractor"
require_relative "rails_openapi_generator/param_extractor"
require_relative "rails_openapi_generator/schema_mapper"
require_relative "rails_openapi_generator/operation_builder"
require_relative "rails_openapi_generator/document_builder"
require_relative "rails_openapi_generator/writer"
require_relative "rails_openapi_generator/generator"
require_relative "rails_openapi_generator/cli"

# Generates a single OpenAPI 3.1 document for a Rails application.
module RailsOpenapiGenerator
  class << self
    # The process-wide configuration. Host apps usually set this via {.configure}.
    def configuration
      @configuration ||= Configuration.new
    end

    # Yields the configuration for the host app to customize.
    def configure
      yield configuration
      configuration
    end

    # Replaces the configuration with a fresh default instance (used by tests).
    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end

require_relative "rails_openapi_generator/railtie" if defined?(Rails::Railtie)
