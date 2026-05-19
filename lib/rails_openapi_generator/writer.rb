# frozen_string_literal: true

require "json"
require "yaml"
require "fileutils"

module RailsOpenapiGenerator
  # Serializes an OpenAPI document Hash to a JSON or YAML file.
  class Writer
    def initialize(configuration)
      @configuration = configuration
    end

    # Writes the document and returns the absolute path written.
    def write(document)
      path = File.expand_path(@configuration.output_path)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, serialize(document))
      path
    end

    # Returns the serialized string for the document in the configured format.
    def serialize(document)
      case @configuration.format
      when :yaml then YAML.dump(document)
      else "#{JSON.pretty_generate(document)}\n"
      end
    end
  end
end
