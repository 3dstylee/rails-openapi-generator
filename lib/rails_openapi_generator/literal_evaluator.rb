# frozen_string_literal: true

module RailsOpenapiGenerator
  # Converts a Ripper literal node into a plain Ruby value. Shared by the
  # parameter path ({ParamExtractor}) and the response path ({RenderExtractor}).
  # Any node that is not a static literal evaluates to {UNRESOLVED}.
  module LiteralEvaluator
    # Sentinel for a value that cannot be statically resolved.
    UNRESOLVED = :__rog_unresolved__

    class << self
      # The {ConstantResolver} instance the evaluator delegates to when a
      # constant-reference node is encountered. The {Generator} sets this
      # at the start of each run; unit specs that don't opt into constant
      # resolution leave it `nil`, in which case constant references
      # evaluate to {UNRESOLVED} (the pre-0.12.0 behavior).
      attr_accessor :resolver
    end

    module_function

    # Returns the Ruby value of a literal Ripper node, or {UNRESOLVED}.
    def evaluate(node)
      return UNRESOLVED unless node.is_a?(Array)

      case node[0]
      when :@int             then Integer(node[1], exception: false) || UNRESOLVED
      when :@float           then Float(node[1], exception: false) || UNRESOLVED
      when :@tstring_content then node[1] # bare word from a %w[...] array
      when :string_literal   then string_value(node)
      when :symbol_literal, :symbol, :dyna_symbol then symbol_value(node)
      when :regexp_literal   then regexp_value(node)
      when :array            then array_value(node[1])
      when :dot2             then range_value(node, exclude_end: false)
      when :dot3             then range_value(node, exclude_end: true)
      when :var_ref          then var_ref_value(node[1])
      when :const_path_ref   then const_path_value(node)
      when :top_const_ref    then const_value_for(node[1].is_a?(Array) ? node[1][1] : nil)
      when :hash             then hash_value(node[1])
      when :bare_assoc_hash  then assoc_hash(node[1])
      else UNRESOLVED
      end
    end

    # A `:var_ref` carries either a `:@kw` (true/false/nil), a `:@const`
    # (a bare constant reference), or a `:@ident` (a local variable —
    # not statically known).
    def var_ref_value(child)
      return UNRESOLVED unless child.is_a?(Array)

      case child[0]
      when :@kw    then keyword_value(child)
      when :@const then const_value_for(child[1])
      else UNRESOLVED
      end
    end

    def keyword_value(node)
      return UNRESOLVED unless node.is_a?(Array) && node[0] == :@kw

      { "true" => true, "false" => false, "nil" => nil }.fetch(node[1], UNRESOLVED)
    end

    # `A::B::C` parses right-associatively: the LEFT child is either a
    # `:var_ref` (the head, like `A`), a `:top_const_ref` (`::A`), or
    # another `:const_path_ref` (chained). Build the joined qualified
    # name and delegate to the resolver.
    def const_path_value(node)
      name = const_path_qualified_name(node)
      const_value_for(name)
    end

    def const_path_qualified_name(node)
      return nil unless node.is_a?(Array)

      case node[0]
      when :const_path_ref
        left = const_path_qualified_name(node[1])
        right = node[2].is_a?(Array) && node[2][0] == :@const ? node[2][1] : nil
        left && right ? "#{left}::#{right}" : nil
      when :top_const_ref
        node[1].is_a?(Array) && node[1][0] == :@const ? node[1][1] : nil
      when :var_ref
        child = node[1]
        child.is_a?(Array) && child[0] == :@const ? child[1] : nil
      end
    end

    def const_value_for(name)
      return UNRESOLVED if name.nil? || resolver.nil?

      resolver.resolve(name)
    end

    def string_value(node)
      content = node[1]
      return UNRESOLVED unless content.is_a?(Array) && content[0] == :string_content

      parts = content[1..].map { |part| part.is_a?(Array) && part[0] == :@tstring_content ? part[1] : UNRESOLVED }
      parts.include?(UNRESOLVED) ? UNRESOLVED : parts.join
    end

    def symbol_value(node)
      return UNRESOLVED unless node.is_a?(Array)

      case node[0]
      when :symbol_literal then symbol_value(node[1])
      when :symbol         then node[1].is_a?(Array) && node[1][1].is_a?(String) ? node[1][1] : UNRESOLVED
      else UNRESOLVED
      end
    end

    def regexp_value(node)
      parts = Array(node[1]).map { |part| part.is_a?(Array) && part[0] == :@tstring_content ? part[1] : UNRESOLVED }
      parts.include?(UNRESOLVED) ? UNRESOLVED : parts.join
    end

    def array_value(elements)
      values = Array(elements).map { |element| evaluate(element) }
      values.include?(UNRESOLVED) ? UNRESOLVED : values
    end

    def range_value(node, exclude_end:)
      first = evaluate(node[1])
      last  = evaluate(node[2])
      return UNRESOLVED if [first, last].include?(UNRESOLVED)

      Range.new(first, last, exclude_end)
    end

    # `:hash` node — node[1] is `[:assoclist_from_args, assocs]` or nil.
    def hash_value(node)
      return {} if node.nil?
      return UNRESOLVED unless node.is_a?(Array) && node[0] == :assoclist_from_args

      assoc_hash(node[1])
    end

    # Builds a Ruby Hash from a list of `:assoc_new` nodes. An unresolvable key
    # collapses the whole hash to UNRESOLVED; unresolvable values are kept.
    def assoc_hash(assocs)
      result = {}
      Array(assocs).each do |assoc|
        return UNRESOLVED unless assoc.is_a?(Array) && assoc[0] == :assoc_new

        key = assoc_key(assoc[1])
        return UNRESOLVED if key == UNRESOLVED

        result[key] = evaluate(assoc[2])
      end
      result
    end

    def assoc_key(node)
      return UNRESOLVED unless node.is_a?(Array)

      case node[0]
      when :@label
        node[1].sub(/:\z/, "").to_sym
      when :symbol_literal, :symbol
        value = symbol_value(node)
        value == UNRESOLVED ? UNRESOLVED : value.to_sym
      when :string_literal
        string_value(node)
      else
        UNRESOLVED
      end
    end

    # Converts a resolved Ruby value into an OpenAPI 3.1 schema Hash. Unknown or
    # unresolvable values become the permissive empty schema `{}` — "any" (R3).
    #
    # UNRESOLVED is checked first because the sentinel is itself a Symbol and
    # must NOT be typed as a string. (Symbol *literals* in source are evaluated
    # to Ruby Strings upstream, so a bare Symbol here only ever means UNRESOLVED.)
    def schema_for(value)
      return {} if value == UNRESOLVED

      case value
      when ::String    then { "type" => "string" }
      when ::Integer   then { "type" => "integer" }
      when ::Float     then { "type" => "number" }
      when true, false then { "type" => "boolean" }
      when ::Array     then array_schema(value)
      when ::Hash      then hash_schema(value)
      else {} # nil, or any value whose type is not known
      end
    end

    def array_schema(value)
      { "type" => "array", "items" => value.empty? ? {} : schema_for(value.first) }
    end

    def hash_schema(value)
      properties = value.each_with_object({}) do |(key, item), result|
        result[key.to_s] = schema_for(item)
      end
      { "type" => "object", "properties" => properties }
    end
  end
end
