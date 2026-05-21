# frozen_string_literal: true

module RailsOpenapiGenerator
  # One statically resolved `rails_param` `param!` declaration. `nested`
  # (feature 008) carries nested-block declarations: for a `Hash` `param!`
  # with a do-block, an Array of nested {ParamCall} objects (the object's
  # properties); for an `Array` `param!` with a do-block, a single
  # {ParamCall} (the items' shape). Nil for flat `param!` calls.
  ParamCall = Struct.new(
    :name, :type, :required, :constraints, :fully_resolved, :nested,
    keyword_init: true
  ) do
    def fully_resolved?
      fully_resolved
    end
  end

  # Extracts `param!` declarations from a controller action's Ripper AST.
  # Literal argument values are resolved via the shared {LiteralEvaluator};
  # non-literal arguments are flagged. Nested `param!` blocks (feature 008)
  # are walked recursively up to `max_depth` levels, producing a tree on
  # the parent {ParamCall}'s `nested` field.
  class ParamExtractor
    DEFAULT_MAX_DEPTH = 5

    # rails-param's symbol-form type shorthands (e.g. `:boolean`), mapped
    # to the canonical class name SchemaMapper indexes by (feature 023).
    SYMBOL_TYPE_ALIASES = {
      "boolean" => "Boolean"
    }.freeze

    def initialize(max_depth: DEFAULT_MAX_DEPTH)
      @max_depth = max_depth
    end

    # Returns an Array of {ParamCall} for the given {ActionSource}.
    def extract(action_source)
      return [] if action_source.nil? || action_source.method_node.nil?

      find_param_calls(action_source.method_node).map { |found| build_call(found, depth: 0) }
    end

    private

    # Walks the AST for top-level `param!` calls. Each match is captured
    # as `{ args:, block: }` — `block` is the `:do_block` / `:brace_block`
    # AST node when present, nil otherwise. The walker skips INTO the
    # body of a matched `:method_add_block` (nested `param!` calls are
    # walked separately by `extract_nested_calls`).
    def find_param_calls(node, calls = [])
      return calls unless node.is_a?(Array)

      found = param_bang_match(node)
      if found
        calls << found
        # Walk siblings, but skip the matched node's own children — its
        # block body is walked by `extract_nested_calls` during build.
        return calls
      end

      node.each { |child| find_param_calls(child, calls) if child.is_a?(Array) }
      calls
    end

    # Returns `{ args:, block: }` for a `param!` call node, or nil.
    # Detects three shapes:
    #   :command — `param! :name, Type`
    #   :method_add_arg — `param!(:name, Type)`
    #   :method_add_block — `param! :name, Hash do |q| ... end`
    def param_bang_match(node)
      case node[0]
      when :command
        args = args_list(node[2]) if ident?(node[1], "param!")
        args && { args: args, block: nil }
      when :method_add_arg
        inner = node[1]
        return nil unless inner.is_a?(Array) && inner[0] == :fcall && ident?(inner[1], "param!")

        paren = node[2]
        args = paren.is_a?(Array) && paren[0] == :arg_paren ? args_list(paren[1]) : nil
        args && { args: args, block: nil }
      when :method_add_block
        inner_args = param_bang_match(node[1])
        return nil unless inner_args

        { args: inner_args[:args], block: node[2] }
      end
    end

    def args_list(node)
      return [] unless node.is_a?(Array) && node[0] == :args_add_block

      Array(node[1])
    end

    def build_call(found, depth:)
      args = found[:args]
      block = found[:block]

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
          type = const_value(arg) || symbol_type_value(arg)
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
        fully_resolved: resolved,
        nested: nested_for(type, block, depth)
      )
    end

    # Builds the `nested` tree when the call carries a do-block AND the
    # type admits nesting (`Hash` or `Array`) AND the depth is within
    # the configured bound. Otherwise returns nil — preserving today's
    # flat behavior (SC-005 / FR-009).
    def nested_for(type, block, depth)
      return nil unless block && %w[Hash Array].include?(type)
      return nil if depth >= @max_depth

      block_vars = block_var_names(block)
      return nil if block_vars.empty?

      body = block_body(block)
      return nil if body.nil?

      nested_calls = extract_nested_calls(body, block_vars).map do |found|
        build_call(found, depth: depth + 1)
      end

      case type
      when "Hash"  then nested_calls
      when "Array" then nested_calls.last
      end
    end

    # Captures the block's parameter names from the
    # [:block_var, [:params, [[:@ident, NAME, ...], ...]], ...] AST.
    def block_var_names(block_node)
      var_node = block_node[1]
      return [] unless var_node.is_a?(Array) && var_node[0] == :block_var

      params = var_node[1]
      return [] unless params.is_a?(Array) && params[0] == :params

      Array(params[1]).filter_map do |param|
        param.is_a?(Array) && param[0] == :@ident ? param[1] : nil
      end
    end

    # Returns the statement list inside the block body, or nil.
    def block_body(block_node)
      case block_node[0]
      when :do_block
        bodystmt = block_node[2]
        bodystmt.is_a?(Array) && bodystmt[0] == :bodystmt ? bodystmt[1] : nil
      when :brace_block
        block_node[2]
      end
    end

    # Walks `body` for `:command_call` and `:method_add_block` nodes
    # whose call is `<blockvar>.param! ...` (one of `block_vars`).
    # Skips `:def` / `:defs` subtrees. Returns each match as
    # `{ args:, block: }`.
    def extract_nested_calls(body, block_vars, found = [])
      return found unless body.is_a?(Array)
      return found if %i[def defs].include?(body[0])

      match = nested_param_match(body, block_vars)
      if match
        found << match
        return found
      end

      body.each { |child| extract_nested_calls(child, block_vars, found) if child.is_a?(Array) }
      found
    end

    # Matches `<blockvar>.param! ...` (bare) or the same wrapped in
    # `:method_add_block` (for further nesting). Returns
    # `{ args:, block: }` or nil.
    def nested_param_match(node, block_vars)
      case node[0]
      when :command_call
        return nil unless var_ref_in?(node[1], block_vars) && ident?(node[3], "param!")

        { args: args_list(node[4]), block: nil }
      when :method_add_block
        inner = nested_param_match(node[1], block_vars)
        return nil unless inner

        { args: inner[:args], block: node[2] }
      end
    end

    def var_ref_in?(node, names)
      node.is_a?(Array) && node[0] == :var_ref &&
        node[1].is_a?(Array) && node[1][0] == :@ident && names.include?(node[1][1])
    end

    def ident?(node, name)
      node.is_a?(Array) && node[0] == :@ident && node[1] == name
    end

    def hash_node?(node)
      node.is_a?(Array) && node[0] == :bare_assoc_hash
    end

    # The parameter name from a leading symbol-literal argument, as a String.
    # Returns nil for an Array-item declaration whose name is a bare ident
    # (e.g. `array.param! i, String` where `i` is the block-index param).
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

    # Resolves a symbol-form type shorthand (`:boolean`) to its canonical
    # class name (`"Boolean"`). Returns nil for an unrecognized symbol so
    # the caller treats the type as unresolved.
    def symbol_type_value(node)
      value = LiteralEvaluator.evaluate(node)
      return nil unless value.is_a?(String)

      SYMBOL_TYPE_ALIASES[value]
    end
  end
end
