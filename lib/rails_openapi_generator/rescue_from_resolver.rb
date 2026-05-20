# frozen_string_literal: true

require "ripper"

module RailsOpenapiGenerator
  # One resolved `rescue_from` declaration on a controller class chain.
  # `exception_name` is informational (e.g.
  # `"ActiveRecord::RecordNotFound"`); it is NOT emitted to OpenAPI.
  # `method_node` is the handler's Ripper AST node — the method body for
  # a Symbol handler, the block body for a Proc handler. The Generator
  # walks this node via {RenderExtractor.collect_sites} to discover
  # response sites that contribute to every operation on the controller.
  RescueFromHandler = Struct.new(:exception_name, :method_node, keyword_init: true)

  # Reads `controller_class.rescue_handlers` (an Array of
  # `[exception_class_string, Symbol|Proc]`) and resolves each handler's
  # body to a Ripper AST. Caches results per-controller-class for the
  # lifetime of one generator run.
  #
  # Any `StandardError` raised during resolution is silently rescued —
  # the resolver returns whatever it could resolve, never raises.
  class RescueFromResolver
    def initialize(method_resolver:)
      @method_resolver = method_resolver
      @cache = {}
    end

    # Returns an `Array<RescueFromHandler>` for the controller class.
    # Returns `[]` for a nil class, a class that doesn't respond to
    # `rescue_handlers`, or any resolution failure.
    def resolve(controller_class)
      return [] if controller_class.nil?
      return @cache[controller_class] if @cache.key?(controller_class)

      @cache[controller_class] = build_handlers(controller_class)
    rescue StandardError
      @cache[controller_class] = []
    end

    private

    def build_handlers(controller_class)
      return [] unless controller_class.respond_to?(:rescue_handlers)

      Array(controller_class.rescue_handlers).filter_map do |entry|
        next unless entry.is_a?(Array) && entry.size == 2

        exception_name, handler = entry
        method_node = resolve_handler(controller_class, handler)
        next if method_node.nil?

        RescueFromHandler.new(exception_name: exception_name, method_node: method_node)
      end
    end

    def resolve_handler(controller_class, handler)
      case handler
      when Symbol then resolve_symbol_handler(controller_class, handler)
      when Proc   then resolve_proc_handler(handler)
      end
    end

    def resolve_symbol_handler(controller_class, method_name)
      resolved = @method_resolver.resolve(controller_class, method_name)
      resolved&.node
    end

    # Locates the AST for `rescue_from Klass do |e| ... end` by parsing
    # the proc's source file with Ripper and finding the do-block whose
    # first source line matches `proc.source_location[1]`.
    def resolve_proc_handler(proc_handler)
      file, line = proc_handler.source_location
      return nil if file.nil? || line.nil? || !File.file?(file)

      sexp = Ripper.sexp(File.read(file))
      return nil if sexp.nil?

      find_rescue_from_block(sexp, line)
    rescue StandardError
      nil
    end

    # Walks the AST for `:method_add_block` nodes whose call is
    # `rescue_from` and whose block starts at `target_line`.
    def find_rescue_from_block(node, target_line, found = [nil])
      return found[0] unless node.is_a?(Array)
      return found[0] unless found[0].nil?

      if rescue_from_method_add_block?(node)
        block = node[2]
        if block.is_a?(Array) && %i[do_block brace_block].include?(block[0]) &&
           block_first_line(block) == target_line
          found[0] = block_body_ast(block)
          return found[0]
        end
      end

      node.each { |child| find_rescue_from_block(child, target_line, found) if child.is_a?(Array) }
      found[0]
    end

    def rescue_from_method_add_block?(node)
      return false unless node[0] == :method_add_block

      call = node[1]
      return false unless call.is_a?(Array) && call[0] == :command

      ident = call[1]
      ident.is_a?(Array) && ident[0] == :@ident && ident[1] == "rescue_from"
    end

    # Returns the first source line of the block body's first statement,
    # via the line stored in the block-arg ident or the body's first
    # node. We rely on `:@ident NAME, [line, col]` token positions.
    def block_first_line(block_node)
      var_node = block_node[1]
      if var_node.is_a?(Array) && var_node[0] == :block_var
        params = var_node[1]
        first = params.is_a?(Array) && params[0] == :params ? Array(params[1]).first : nil
        return first[2][0] if first.is_a?(Array) && first[2].is_a?(Array)
      end

      # Fallback — try the first statement's position.
      body = block_body_ast(block_node)
      first_stmt = body.is_a?(Array) ? body.find { |s| s.is_a?(Array) } : nil
      first_stmt && first_stmt.last.is_a?(Array) ? first_stmt.last[0] : nil
    end

    def block_body_ast(block_node)
      case block_node[0]
      when :do_block
        bodystmt = block_node[2]
        bodystmt.is_a?(Array) && bodystmt[0] == :bodystmt ? bodystmt[1] : nil
      when :brace_block
        block_node[2]
      end
    end
  end
end
