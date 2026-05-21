# frozen_string_literal: true

require "set"

module RailsOpenapiGenerator
  # Walks every receiverless helper method reached from a root node and
  # returns each helper's body with the call site's literal argument
  # values substituted in for the helper's parameter references. Bindings
  # compose through nested calls — the substituted body's own helper
  # calls see the outer literals.
  #
  # Recursion is bounded by `max_depth`; no per-location dedup of call
  # sites — a helper called twice with different literals contributes two
  # substituted bodies (FR-006). The root node itself is NOT included in
  # the returned list — the caller already collects render sites from it
  # via `RenderExtractor#extract` (for actions) or `collect_sites` (for
  # callbacks and rescue handlers).
  class HelperBindingWalker
    def initialize(method_resolver:, max_depth: 5)
      @method_resolver = method_resolver
      @max_depth = max_depth
    end

    # Returns substituted helper bodies reachable from `root`.
    def reachable_bodies(controller_class, root)
      return [] if root.nil? || controller_class.nil?

      bodies = []
      walk(controller_class, root, 0, bodies)
      bodies
    end

    private

    def walk(controller_class, node, depth, bodies)
      return if depth >= @max_depth

      receiverless_calls(node).each do |call|
        resolved = @method_resolver.resolve(controller_class, call[:name])
        next if resolved.nil?

        bindings = bind_args(resolved.node, call[:args])
        substituted = substitute(body_of(resolved.node), bindings)
        bodies << substituted
        walk(controller_class, substituted, depth + 1, bodies)
      end
    end

    # Every receiverless method call in the subtree, returned as
    # `{ name:, args: }` pairs. Mirrors the call-name extraction in
    # {ControllerMethodWalker.receiverless_call_names} but also captures
    # each call's argument-node list.
    def receiverless_calls(node, calls = [])
      return calls unless node.is_a?(Array)

      call = receiverless_call(node)
      calls << call if call

      node.each { |child| receiverless_calls(child, calls) if child.is_a?(Array) }
      calls
    end

    def receiverless_call(node)
      case node[0]
      when :vcall
        ident = node[1]
        ident_name(ident) && { name: ident_name(ident), args: [] }
      when :fcall
        # Bare `fcall` without args — the wrapping `method_add_arg` form
        # provides the args. Skip here to avoid double-counting.
        nil
      when :command
        ident_name(node[1]) && { name: ident_name(node[1]), args: command_args(node[2]) }
      when :method_add_arg
        inner = node[1]
        return nil unless inner.is_a?(Array) && inner[0] == :fcall && ident_name(inner[1])

        { name: ident_name(inner[1]), args: paren_args(node[2]) }
      end
    end

    def ident_name(node)
      node.is_a?(Array) && node[0] == :@ident ? node[1] : nil
    end

    def command_args(node)
      node.is_a?(Array) && node[0] == :args_add_block ? Array(node[1]) : []
    end

    def paren_args(node)
      node.is_a?(Array) && node[0] == :arg_paren ? command_args(node[1]) : []
    end

    # The bodystmt sub-array of a `[:def, ident, params, bodystmt]` node.
    # Returning the full def node would expose the params subtree to the
    # substitutor; returning the bodystmt scopes substitution to the
    # method body only.
    def body_of(def_node)
      def_node.is_a?(Array) && def_node[0] == :def ? def_node[3] : def_node
    end

    # Binds the call's literal arguments to the resolved method's params.
    # Positional args map by position to the helper's required +
    # optional positional params. A `:bare_assoc_hash` argument carries
    # keyword args, mapped by name to the helper's keyword params.
    # Unbound params (splat, block, missing args) are simply absent from
    # the returned Hash — their references in the body stay UNRESOLVED.
    def bind_args(def_node, args)
      params = extract_params(def_node)
      return {} if params.nil?

      positional_args, kwarg_node = split_args(args)
      bindings = {}
      params[:positional].each_with_index do |name, i|
        bindings[name] = positional_args[i] if positional_args[i]
      end
      params[:keyword].each do |name|
        node = kwarg_value(kwarg_node, name)
        bindings[name] = node if node
      end
      bindings
    end

    # Returns `{ positional: [name, ...], keyword: [name, ...] }` for a
    # `[:def, ident, params_paren, bodystmt]` node, or nil when params
    # cannot be read.
    def extract_params(def_node)
      return nil unless def_node.is_a?(Array) && def_node[0] == :def

      params_node = unwrap_paren(def_node[2])
      return nil unless params_node.is_a?(Array) && params_node[0] == :params

      { positional: positional_param_names(params_node), keyword: keyword_param_names(params_node) }
    end

    def unwrap_paren(node)
      node.is_a?(Array) && node[0] == :paren ? node[1] : node
    end

    # required (`[[ident], ...]`) + optionals (`[[[ident, default]], ...]`).
    def positional_param_names(params_node)
      required = Array(params_node[1]).filter_map { |ident| ident_name(ident) }
      optional = Array(params_node[2]).filter_map { |pair| ident_name(pair.is_a?(Array) ? pair[0] : nil) }
      required + optional
    end

    # `[[[:@label, "name:", pos], default_or_false], ...]` — strip the trailing `:`.
    def keyword_param_names(params_node)
      Array(params_node[5]).filter_map do |pair|
        label = pair.is_a?(Array) ? pair[0] : nil
        next nil unless label.is_a?(Array) && label[0] == :@label

        label[1].chomp(":")
      end
    end

    # Returns `[positional_arg_nodes, kwarg_bare_assoc_hash_node_or_nil]`.
    # A trailing `:bare_assoc_hash` argument is the kwarg bucket.
    def split_args(args)
      kwarg = args.last if args.last.is_a?(Array) && args.last[0] == :bare_assoc_hash
      positional = kwarg ? args[0..-2] : args
      [positional, kwarg]
    end

    # The value AST node bound to keyword `name` in a bare_assoc_hash
    # node, or nil when the kwarg is absent. `bare_assoc_hash` shape:
    # `[:bare_assoc_hash, [[:assoc_new, label_or_key, value], ...]]`.
    def kwarg_value(kwarg_node, name)
      return nil unless kwarg_node.is_a?(Array) && kwarg_node[0] == :bare_assoc_hash

      Array(kwarg_node[1]).each do |pair|
        next unless pair.is_a?(Array) && pair[0] == :assoc_new

        key = pair[1]
        key_name = case key && key[0]
                   when :@label then key[1].chomp(":")
                   when :symbol_literal then symbol_literal_name(key)
                   end
        return pair[2] if key_name == name
      end
      nil
    end

    def symbol_literal_name(node)
      inner = node[1]
      return nil unless inner.is_a?(Array) && inner[0] == :symbol
      return nil unless inner[1].is_a?(Array) && inner[1][1].is_a?(String)

      inner[1][1]
    end

    # Deep-walks `node` and returns a NEW AST in which every
    # `[:var_ref, [:@ident, name]]` whose `name` is in `bindings` is
    # replaced by the bound AST node. Other subtrees are returned
    # unchanged (shared with the input — substitution is non-mutating
    # and the input AST is treated as immutable).
    def substitute(node, bindings)
      return node if bindings.empty?
      return node unless node.is_a?(Array)

      if var_ref_ident?(node)
        name = node[1][1]
        return bindings.fetch(name, node)
      end

      node.map { |child| child.is_a?(Array) ? substitute(child, bindings) : child }
    end

    def var_ref_ident?(node)
      node[0] == :var_ref && node[1].is_a?(Array) && node[1][0] == :@ident
    end
  end
end
