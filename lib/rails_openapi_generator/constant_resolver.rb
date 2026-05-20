# frozen_string_literal: true

module RailsOpenapiGenerator
  # Resolves a Ruby constant by qualified name via `Object.const_get`,
  # validates the resolved value against the schema-compatible set
  # ({String}/{Symbol}/{Integer}/{Float}/Boolean primitives, {Array} /
  # {Hash} of recursively-compatible values, {Range} of Integers or
  # Floats, {Regexp}), and caches each result per-instance for the
  # lifetime of one generator run.
  #
  # Any `StandardError` (including `NameError`) or `LoadError` raised
  # during the lookup is silently rescued — the resolver returns
  # {LiteralEvaluator::UNRESOLVED}, never raises. The generator's
  # existing "non-literal param! arguments" warning continues to fire
  # for that parameter (same observable behavior as today).
  class ConstantResolver
    def initialize
      @cache = {}
    end

    # Returns the resolved Ruby value, or {LiteralEvaluator::UNRESOLVED}
    # when the constant cannot be loaded or its value is not
    # schema-compatible.
    def resolve(qualified_name)
      return LiteralEvaluator::UNRESOLVED if qualified_name.nil? || qualified_name.empty?
      return @cache[qualified_name] if @cache.key?(qualified_name)

      @cache[qualified_name] = lookup_and_filter(qualified_name)
    end

    private

    def lookup_and_filter(qualified_name)
      value = Object.const_get(qualified_name, true)
      schema_compatible?(value) ? value : LiteralEvaluator::UNRESOLVED
    rescue StandardError, LoadError
      LiteralEvaluator::UNRESOLVED
    end

    # The narrow set of Ruby value shapes the downstream
    # {SchemaMapper} can safely map to OpenAPI schema fields.
    def schema_compatible?(value)
      case value
      when ::String, ::Symbol, ::Integer, ::Float, true, false, ::Regexp
        true
      when ::Range
        bounds_compatible?(value.begin, value.end)
      when ::Array
        value.all? { |element| schema_compatible?(element) }
      when ::Hash
        value.all? { |k, v| (k.is_a?(::String) || k.is_a?(::Symbol)) && schema_compatible?(v) }
      else
        false
      end
    end

    # A Range is schema-compatible when both ends are Integer or both
    # are Float (mixed-numeric Ranges aren't directly mappable).
    def bounds_compatible?(low, high)
      (low.is_a?(::Integer) && high.is_a?(::Integer)) ||
        (low.is_a?(::Float) && high.is_a?(::Float))
    end
  end
end
