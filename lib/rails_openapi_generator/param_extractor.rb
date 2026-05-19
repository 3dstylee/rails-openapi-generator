# frozen_string_literal: true

module RailsOpenapiGenerator
  # One statically resolved `rails_param` `param!` declaration.
  ParamCall = Struct.new(:name, :type, :required, :constraints, :fully_resolved, keyword_init: true) do
    def fully_resolved?
      fully_resolved
    end
  end

  # Extracts `param!` declarations from a controller action's Ripper AST.
  # Literal argument values are resolved via the shared {LiteralEvaluator};
  # non-literal arguments are flagged.
  class ParamExtractor
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
      name     = symbol_value(args[0])
      type     = nil
      options  = {}
      resolved = !name.nil?

      args[1..].each do |arg|
        if hash_node?(arg)
          evaluated = LiteralEvaluator.evaluate(arg)
          options   = evaluated.is_a?(Hash) ? evaluated : {}
          resolved  = false unless evaluated.is_a?(Hash) && !options.value?(LiteralEvaluator::UNRESOLVED)
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
        constraints: options.reject { |_, value| value == LiteralEvaluator::UNRESOLVED },
        fully_resolved: resolved
      )
    end

    def ident?(node, name)
      node.is_a?(Array) && node[0] == :@ident && node[1] == name
    end

    def hash_node?(node)
      node.is_a?(Array) && node[0] == :bare_assoc_hash
    end

    # The parameter name from a leading symbol-literal argument, as a String.
    def symbol_value(node)
      return nil unless node.is_a?(Array)

      case node[0]
      when :symbol_literal then symbol_value(node[1])
      when :symbol         then node[1].is_a?(Array) && node[1][1].is_a?(String) ? node[1][1] : nil
      end
    end

    # The trailing constant name of a type argument, e.g. Integer or ActiveSupport::X.
    def const_value(node)
      return nil unless node.is_a?(Array)

      case node[0]
      when :var_ref, :vcall then const_value(node[1])
      when :const_path_ref  then const_value(node[2])
      when :@const          then node[1]
      end
    end
  end
end
