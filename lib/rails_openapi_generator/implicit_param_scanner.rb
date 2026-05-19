# frozen_string_literal: true

module RailsOpenapiGenerator
  # Scans a controller action — and the receiverless helper methods it calls —
  # for request parameters used implicitly via the `params` object: index
  # access (`params[:key]`) and strong-params calls (`require`, `permit`,
  # `fetch`, `dig`). Only literal keys are collected; no code is executed.
  class ImplicitParamScanner
    STRONG_PARAM_METHODS = %w[require permit fetch dig].freeze
    RAILS_INTERNAL_KEYS  = %w[controller action format].freeze

    def initialize(walker:)
      @walker = walker
    end

    # Returns the sorted, unique implicit parameter names for the action,
    # excluding Rails-internal keys.
    def scan(controller_class, action_node)
      return [] if action_node.nil?

      keys = @walker.reachable_bodies(controller_class, action_node).flat_map { |body| params_keys(body) }
      keys.uniq.reject { |key| RAILS_INTERNAL_KEYS.include?(key) }.sort
    end

    private

    def params_keys(node, keys = [])
      return keys unless node.is_a?(Array)

      keys.concat(index_keys(node))
      keys.concat(strong_param_keys(node))
      node.each { |child| params_keys(child, keys) if child.is_a?(Array) }
      keys
    end

    # Keys read via `params[:key]` index access.
    def index_keys(node)
      return [] unless node[0] == :aref && params_object?(node[1])

      literal_keys(arg_list(node[2]))
    end

    # Keys named in `require`/`permit`/`fetch`/`dig` calls on the params object
    # (including calls chained on a `params` strong-params result).
    def strong_param_keys(node)
      method, receiver, args = strong_call(node)
      return [] unless method && STRONG_PARAM_METHODS.include?(method) && params_chain?(receiver)

      literal_keys(args)
    end

    # Returns [method_name, receiver_node, arg_nodes] for a method call, or [].
    def strong_call(node)
      case node[0]
      when :command_call
        [method_name(node[3]), node[1], arg_list(node[4])]
      when :method_add_arg
        inner = node[1]
        return [] unless inner.is_a?(Array) && inner[0] == :call

        [method_name(inner[3]), inner[1], arg_list(node[2])]
      when :call
        [method_name(node[3]), node[1], []]
      else
        []
      end
    end

    # True when the node is the `params` object or a strong-params call on it.
    def params_chain?(node)
      return false unless node.is_a?(Array)
      return true if params_object?(node)

      method, receiver, = strong_call(node)
      method && STRONG_PARAM_METHODS.include?(method) && params_chain?(receiver)
    end

    def params_object?(node)
      node.is_a?(Array) && %i[vcall var_ref].include?(node[0]) &&
        node[1].is_a?(Array) && node[1][0] == :@ident && node[1][1] == "params"
    end

    def method_name(node)
      node.is_a?(Array) && node[0] == :@ident ? node[1] : nil
    end

    def arg_list(node)
      return [] unless node.is_a?(Array)

      case node[0]
      when :args_add_block then Array(node[1])
      when :arg_paren      then arg_list(node[1])
      else []
      end
    end

    def literal_keys(arg_nodes)
      arg_nodes.filter_map do |arg|
        value = LiteralEvaluator.evaluate(arg)
        value if value.is_a?(String)
      end
    end
  end
end
