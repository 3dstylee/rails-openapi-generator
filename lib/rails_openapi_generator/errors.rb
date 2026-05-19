# frozen_string_literal: true

module RailsOpenapiGenerator
  # Base class for all errors raised by the gem.
  class Error < StandardError; end

  # Raised for invalid configuration before any generation work begins.
  class ConfigurationError < Error; end
end
