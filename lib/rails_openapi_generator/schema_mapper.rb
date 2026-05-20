# frozen_string_literal: true

module RailsOpenapiGenerator
  # Translates a {ParamCall}'s type and constraints into an OpenAPI 3.1 schema Hash.
  class SchemaMapper
    TYPE_MAP = {
      "String" => { "type" => "string" },
      "Integer" => { "type" => "integer" },
      "Float" => { "type" => "number" },
      "BigDecimal" => { "type" => "number" },
      "Numeric" => { "type" => "number" },
      "TrueClass" => { "type" => "boolean" },
      "FalseClass" => { "type" => "boolean" },
      "Boolean" => { "type" => "boolean" },
      "Array" => { "type" => "array" },
      "Hash" => { "type" => "object" },
      "Date" => { "type" => "string", "format" => "date" },
      "DateTime" => { "type" => "string", "format" => "date-time" },
      "Time" => { "type" => "string", "format" => "date-time" }
    }.freeze

    DEFAULT_SCHEMA = { "type" => "string" }.freeze

    # Returns an OpenAPI schema Hash for the given {ParamCall}.
    def map(param_call)
      schema = (TYPE_MAP[param_call.type] || DEFAULT_SCHEMA).dup
      apply_constraints(schema, param_call.constraints || {})
      schema
    end

    private

    def apply_constraints(schema, constraints)
      constraints.each do |key, value|
        case key
        when :in         then apply_inclusion(schema, value)
        when :min        then schema["minimum"] = value
        when :max        then schema["maximum"] = value
        when :min_length then schema["minLength"] = value
        when :max_length then schema["maxLength"] = value
        when :format     then schema["pattern"] = pattern_source(value) if pattern_source(value)
        when :blank      then schema["minLength"] = 1 if value == false && schema["type"] == "string"
        end
      end
      schema
    end

    # A `:format` constraint can be a String (literal regex source from
    # the existing `LiteralEvaluator.regexp_value` path) or a Regexp
    # object (from {ConstantResolver} resolving a Regexp constant).
    def pattern_source(value)
      case value
      when ::String then value
      when ::Regexp then value.source
      end
    end

    def apply_inclusion(schema, value)
      case value
      when Range
        schema["minimum"] = value.first
        if value.exclude_end?
          schema["exclusiveMaximum"] = value.last
        else
          schema["maximum"] = value.last
        end
      when Array
        schema["enum"] = value
      end
    end
  end
end
