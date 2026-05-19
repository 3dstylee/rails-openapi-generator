# frozen_string_literal: true

module RailsOpenapiGenerator
  # One statically resolved `rails_param` `param!` declaration.
  ParamCall = Struct.new(:name, :type, :required, :constraints, :fully_resolved, keyword_init: true) do
    def fully_resolved?
      fully_resolved
    end
  end

  # Extracts `param!` declarations from a controller action's Ripper AST.
  # Only literal arguments are resolved; non-literal arguments are flagged.
  class ParamExtractor
    # Sentinel for an argument value that could not be statically resolved.
    UNRESOLVED = :__rog_unresolved__

    # Returns an Array of {ParamCall} for the given {ActionSource}.
    def extract(action_source)
      return [] if action_source.nil? || action_source.method_node.nil?

      find_param_calls(action_source.method_node).map { |args| build_call(args) }
    end

    private

    def find_param_calls(node, calls = [])
      return calls unless node.is_a?(Array)

      args = param_bang_args(node)
      calls << args if args

      node.each { |child| find_param_calls(child, calls) if child.is_a?(Array) }
      calls
    end

    # Returns the argument-value array for a `param!` call node, or nil.
    def param_bang_args(node)
      case node[0]
      when :command
        ident?(node[1], "param!") ? args_list(node[2]) : nil
      when :method_add_arg
        inner = node[1]
        return nil unless inner.is_a?(Array) && inner[0] == :fcall && ident?(inner[1], "param!")

        paren = node[2]
        paren.is_a?(Array) && paren[0] == :arg_paren ? args_list(paren[1]) : nil
      end
    end

    def args_list(node)
      return [] unless node.is_a?(Array) && node[0] == :args_add_block

      Array(node[1])
    end

    def build_call(args)
      name        = symbol_value(args[0])
      type        = nil
      options     = {}
      resolved    = !name.nil?

      args[1..].each do |arg|
        if hash_node?(arg)
          options = parse_hash(arg)
          resolved = false if options.value?(UNRESOLVED)
        elsif type.nil?
          type = const_value(arg)
          resolved = false if type.nil?
        end
      end

      required = options.delete(:required) == true
      options.delete(:default)

      ParamCall.new(
        name: name,
        type: type,
        required: required,
        constraints: options.reject { |_, value| value == UNRESOLVED },
        fully_resolved: resolved
      )
    end

    def ident?(node, name)
      node.is_a?(Array) && node[0] == :@ident && node[1] == name
    end

    def hash_node?(node)
      node.is_a?(Array) && node[0] == :bare_assoc_hash
    end

    def parse_hash(node)
      Array(node[1]).each_with_object({}) do |assoc, result|
        next unless assoc.is_a?(Array) && assoc[0] == :assoc_new

        key = label_value(assoc[1])
        result[key] = literal_value(assoc[2]) if key
      end
    end

    def label_value(node)
      return nil unless node.is_a?(Array)

      case node[0]
      when :@label then node[1].sub(/:\z/, "").to_sym
      when :symbol_literal then symbol_value(node)&.to_sym
      end
    end

    def symbol_value(node)
      return nil unless node.is_a?(Array)

      case node[0]
      when :symbol_literal then symbol_value(node[1])
      when :symbol         then atom_text(node[1])
      when :dyna_symbol    then nil
      end
    end

    def atom_text(node)
      node.is_a?(Array) && node.size >= 2 && node[1].is_a?(String) ? node[1] : nil
    end

    # The trailing constant name of a type argument, e.g. Integer or ActiveSupport::X.
    def const_value(node)
      return nil unless node.is_a?(Array)

      case node[0]
      when :var_ref, :vcall   then const_value(node[1])
      when :const_path_ref    then const_value(node[2])
      when :@const            then node[1]
      end
    end

    # Converts a Ripper literal node to a Ruby value, or UNRESOLVED.
    def literal_value(node)
      return UNRESOLVED unless node.is_a?(Array)

      case node[0]
      when :@int            then Integer(node[1], exception: false) || UNRESOLVED
      when :@float          then Float(node[1], exception: false) || UNRESOLVED
      when :@tstring_content then node[1] # bare word from a %w[...] array
      when :string_literal  then string_value(node)
      when :symbol_literal  then symbol_value(node)
      when :regexp_literal  then regexp_value(node)
      when :array           then array_value(node[1])
      when :dot2            then range_value(node, exclude_end: false)
      when :dot3            then range_value(node, exclude_end: true)
      when :var_ref         then keyword_value(node[1])
      else UNRESOLVED
      end
    end

    def keyword_value(node)
      return UNRESOLVED unless node.is_a?(Array) && node[0] == :@kw

      { "true" => true, "false" => false, "nil" => nil }.fetch(node[1], UNRESOLVED)
    end

    def string_value(node)
      content = node[1]
      return UNRESOLVED unless content.is_a?(Array) && content[0] == :string_content

      parts = content[1..].map { |part| part.is_a?(Array) && part[0] == :@tstring_content ? part[1] : UNRESOLVED }
      parts.include?(UNRESOLVED) ? UNRESOLVED : parts.join
    end

    def regexp_value(node)
      parts = Array(node[1]).map { |part| part.is_a?(Array) && part[0] == :@tstring_content ? part[1] : UNRESOLVED }
      parts.include?(UNRESOLVED) ? UNRESOLVED : parts.join
    end

    def array_value(elements)
      values = Array(elements).map { |element| literal_value(element) }
      values.include?(UNRESOLVED) ? UNRESOLVED : values
    end

    def range_value(node, exclude_end:)
      first = literal_value(node[1])
      last  = literal_value(node[2])
      return UNRESOLVED if [first, last].include?(UNRESOLVED)

      Range.new(first, last, exclude_end)
    end
  end
end
