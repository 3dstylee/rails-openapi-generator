# frozen_string_literal: true

module RailsOpenapiGenerator
  # User-supplied settings for a generation run.
  class Configuration
    DEFAULT_OUTPUT_PATH = "doc/openapi.json"
    SUPPORTED_FORMATS = %i[json yaml].freeze
    DEFAULT_METHOD_RESOLUTION_DEPTH = 5

    attr_accessor :output_path, :title, :api_version, :route_filter, :method_resolution_depth,
                  :exclude_source_paths
    attr_writer :format

    def initialize
      @output_path  = DEFAULT_OUTPUT_PATH
      @title        = nil
      @api_version  = "1.0.0"
      @route_filter = nil
      @format       = nil
      @method_resolution_depth = DEFAULT_METHOD_RESOLUTION_DEPTH
      @exclude_source_paths = []
    end

    # True when `path` matches any `exclude_source_paths` entry — a String entry
    # by substring, a Regexp entry by pattern. False for a nil path.
    def source_excluded?(path)
      return false if path.nil?

      Array(exclude_source_paths).any? do |pattern|
        pattern.is_a?(Regexp) ? pattern.match?(path) : path.include?(pattern.to_s)
      end
    end

    # The serialization format, inferred from the output path extension when not set explicitly.
    def format
      @format || infer_format
    end

    # Validates the configuration, raising ConfigurationError on any problem.
    def validate!
      unless SUPPORTED_FORMATS.include?(format)
        raise ConfigurationError, "format must be one of #{SUPPORTED_FORMATS.inspect}, got #{format.inspect}"
      end

      raise ConfigurationError, "output_path must be set" if output_path.nil? || output_path.to_s.strip.empty?

      unless writable_destination?
        raise ConfigurationError,
              "output_path directory is not writable: #{File.dirname(File.expand_path(output_path))}"
      end

      unless method_resolution_depth.is_a?(Integer) && method_resolution_depth >= 1
        raise ConfigurationError,
              "method_resolution_depth must be an integer >= 1, got #{method_resolution_depth.inspect}"
      end

      unless exclude_source_paths.is_a?(Array) &&
             exclude_source_paths.all? { |entry| entry.is_a?(String) || entry.is_a?(Regexp) }
        raise ConfigurationError,
              "exclude_source_paths must be an array of strings or regexps, got #{exclude_source_paths.inspect}"
      end

      self
    end

    private

    def infer_format
      case File.extname(output_path.to_s).downcase
      when ".yaml", ".yml" then :yaml
      else :json
      end
    end

    # The output directory may not exist yet; check the nearest existing ancestor.
    def writable_destination?
      dir = File.dirname(File.expand_path(output_path))
      dir = File.dirname(dir) until File.exist?(dir) || dir == File.dirname(dir)
      File.directory?(dir) && File.writable?(dir)
    end
  end
end
