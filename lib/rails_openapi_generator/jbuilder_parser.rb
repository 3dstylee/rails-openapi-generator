# frozen_string_literal: true

require "ripper"

module RailsOpenapiGenerator
  # Statically parses a `.json.jbuilder` template into an OpenAPI response
  # schema. Field names and nesting are recovered; leaf types are best-effort
  # (typed only when read from a literal) per research R3. Constructs that
  # cannot be resolved degrade to a permissive schema — the parse never raises.
  class JbuilderParser
    EXTENSION = ".json.jbuilder"
    # jbuilder calls that do not contribute properties to the schema.
    IGNORED = %w[
      merge! key_format! ignore_nil! deep_format_keys! cache! cache_root! cache_if! nil! null!
    ].freeze

    def initialize(views_root: nil)
      @views_root = views_root
      @cache = {}
    end

    # Returns an OpenAPI schema Hash for the template at `file_path`.
    def parse(file_path)
      schema_for_file(file_path, [])
    end

    private

    def schema_for_file(file_path, seen)
      return permissive_object if file_path.nil? || !File.file?(file_path) || seen.include?(file_path)

      @cache[file_path] ||= begin
        sexp = Ripper.sexp(File.read(file_path))
        sexp ? build_schema(statements(sexp), seen + [file_path]) : permissive_object
      end
    end

    def statements(sexp)
      sexp.is_a?(Array) && sexp[0] == :program ? Array(sexp[1]) : []
    end

    def build_schema(stmts, seen)
      properties  = {}
      array_items = nil
      is_array    = false

      each_json_call(stmts) do |call|
        case call[:method]
        when "array!"
          is_array = true
          array_items = array_items_schema(call, seen)
        when "partial!" then merge_partial(properties, call, seen)
        when "extract!" then extract_properties(properties, call)
        when "set!"     then set_property(properties, call, seen)
        else
          add_property(properties, call, seen) unless IGNORED.include?(call[:method])
        end
      end

      is_array ? { "type" => "array", "items" => array_items || permissive_object } : object_schema(properties)
    end

    # --- statement walking -------------------------------------------------

    def each_json_call(stmts, &block)
      Array(stmts).each { |stmt| visit_statement(stmt, &block) }
    end

    def visit_statement(node, &block)
      return unless node.is_a?(Array)

      call = json_call(node)
      if call
        block.call(call)
      elsif %i[if unless elsif if_mod unless_mod].include?(node[0])
        conditional_bodies(node).each { |body| each_json_call(body, &block) }
      elsif node[0] == :case
        case_branch_bodies(node).each { |body| each_json_call(body, &block) }
      end
    end

    # Gathers every branch body of a conditional (union of branches).
    def conditional_bodies(node)
      case node[0]
      when :if_mod, :unless_mod
        [[node[1]]]
      when :if, :unless, :elsif
        bodies = [Array(node[2])]
        tail = node[3]
        bodies + (tail.is_a?(Array) ? conditional_bodies(tail) : [])
      when :else
        [Array(node[1])]
      else
        []
      end
    end

    # Walks the when/else chain of a [:case, expr, chain] node and returns
    # every branch body. Bodies from every `when` and the optional `else`
    # are unioned, matching the existing if/elsif/else posture.
    def case_branch_bodies(node)
      walk_case_chain(node[2])
    end

    def walk_case_chain(chain)
      return [] unless chain.is_a?(Array)

      case chain[0]
      when :when
        [Array(chain[2])] + walk_case_chain(chain[3])
      when :else
        [Array(chain[1])]
      else
        []
      end
    end

    # --- json.* call recognition ------------------------------------------

    # Returns { method:, args:, block: } for a `json.<method>` call, else nil.
    def json_call(node)
      return nil unless node.is_a?(Array)

      case node[0]
      when :method_add_block
        inner = json_call(node[1])
        inner&.merge(block: node[2])
      when :command_call
        if json_receiver?(node[1]) && method_ident(node[3])
          { method: method_ident(node[3]),
            args: command_args(node[4]), block: nil }
        end
      when :method_add_arg
        call = node[1]
        return nil unless call.is_a?(Array) && call[0] == :call && json_receiver?(call[1]) && method_ident(call[3])

        { method: method_ident(call[3]), args: paren_args(node[2]), block: nil }
      when :call
        json_receiver?(node[1]) && method_ident(node[3]) ? { method: method_ident(node[3]), args: [], block: nil } : nil
      end
    end

    def json_receiver?(node)
      node.is_a?(Array) && %i[vcall var_ref].include?(node[0]) &&
        node[1].is_a?(Array) && node[1][0] == :@ident && node[1][1] == "json"
    end

    def method_ident(node)
      node.is_a?(Array) && node[0] == :@ident ? node[1] : nil
    end

    def command_args(node)
      node.is_a?(Array) && node[0] == :args_add_block ? Array(node[1]) : []
    end

    def paren_args(node)
      node.is_a?(Array) && node[0] == :arg_paren ? command_args(node[1]) : []
    end

    def block_statements(block)
      return [] unless block.is_a?(Array)

      body = block[2]
      case block[0]
      when :do_block    then body.is_a?(Array) && body[0] == :bodystmt ? Array(body[1]) : []
      when :brace_block then Array(body)
      else []
      end
    end

    # --- property assembly -------------------------------------------------

    def add_property(properties, call, seen)
      name = call[:method]
      properties[name] =
        if call[:block]
          block_schema = build_schema(block_statements(call[:block]), seen)
          # A block with a positional argument iterates a collection → array.
          call[:args].empty? ? block_schema : { "type" => "array", "items" => block_schema }
        elsif hash_partial_name(call[:args])
          partial_property_schema(call, seen)
        else
          value_schema(call[:args].first)
        end
    end

    # Schema for a `json.<key> [collection,] partial: "name"` call. With a
    # positional collection arg the key is an array of the partial; without
    # one the partial schema is inlined directly.
    def partial_property_schema(call, seen)
      schema = partial_schema(call, seen) || permissive_object
      positional_arg?(call[:args]) ? { "type" => "array", "items" => schema } : schema
    end

    def positional_arg?(args)
      args.any? { |arg| !(arg.is_a?(Array) && arg[0] == :bare_assoc_hash) }
    end

    # Only matches the `partial:` keyword option. Unlike {#partial_name}, a
    # bare positional String is not treated as a partial — `json.name "n"`
    # is a literal value, not a partial reference.
    def hash_partial_name(args)
      args.each do |arg|
        next unless arg.is_a?(Array) && arg[0] == :bare_assoc_hash

        value = LiteralEvaluator.evaluate(arg)
        return value[:partial] if value.is_a?(Hash) && value[:partial].is_a?(String)
      end
      nil
    end

    def extract_properties(properties, call)
      # json.extract! object, :a, :b — args[0] is the object, the rest are fields.
      call[:args].drop(1).each do |arg|
        name = LiteralEvaluator.evaluate(arg)
        properties[name.to_s] = {} if name.is_a?(String)
      end
    end

    def set_property(properties, call, seen)
      key = LiteralEvaluator.evaluate(call[:args].first)
      return unless key.is_a?(String)

      properties[key] =
        if call[:block]
          build_schema(block_statements(call[:block]), seen)
        else
          value_schema(call[:args][1])
        end
    end

    def merge_partial(properties, call, seen)
      schema = partial_schema(call, seen)
      properties.merge!(schema["properties"]) if schema.is_a?(Hash) && schema["properties"].is_a?(Hash)
    end

    def array_items_schema(call, seen)
      return build_schema(block_statements(call[:block]), seen) if call[:block]

      partial = partial_schema(call, seen)
      partial || permissive_object
    end

    # Resolves the partial named in a json.partial!/json.array! call to a schema.
    def partial_schema(call, seen)
      name = partial_name(call[:args])
      file = resolve_partial(name)
      file ? schema_for_file(file, seen) : nil
    end

    def partial_name(args)
      args.each do |arg|
        value = LiteralEvaluator.evaluate(arg)
        return value if value.is_a?(String)
        return value[:partial] if value.is_a?(Hash) && value[:partial].is_a?(String)
      end
      nil
    end

    def resolve_partial(name)
      return nil if @views_root.nil? || !name.is_a?(String)

      dir  = File.dirname(name)
      base = "_#{File.basename(name)}#{EXTENSION}"
      relative = dir == "." ? base : File.join(dir, base)
      File.join(@views_root, relative)
    end

    def value_schema(arg)
      value = LiteralEvaluator.evaluate(arg)
      value == LiteralEvaluator::UNRESOLVED ? {} : LiteralEvaluator.schema_for(value)
    end

    def object_schema(properties)
      { "type" => "object", "properties" => properties.sort.to_h }
    end

    def permissive_object
      { "type" => "object", "properties" => {} }
    end
  end
end
