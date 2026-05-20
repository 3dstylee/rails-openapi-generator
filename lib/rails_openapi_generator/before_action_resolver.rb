# frozen_string_literal: true

require "ripper"
require "set"

module RailsOpenapiGenerator
  # One `before_action` callback applicable to some set of actions on a
  # controller class.
  #
  # `method_name` is the callback method name (a String). `method_node` is
  # the resolved Ripper AST for that method, or nil when the method cannot
  # be located (the callback is silently skipped). `only` / `except` are
  # `Set<String>` of action names recovered from a literal `only: [...]` /
  # `except: [...]` array on the controller's own source — nil means "no
  # restriction known", which the resolver treats as "applies to every
  # action in this controller" (FR-008).
  BeforeActionCallback = Struct.new(:method_name, :method_node, :only, :except, keyword_init: true) do
    def applies_to?(action_name)
      return false if only && !only.include?(action_name.to_s)
      return false if except&.include?(action_name.to_s)

      true
    end
  end

  # Reads the Rails callback chain for a controller class and returns the
  # `:before` callbacks for `:process_action`, with each callback's method
  # body resolved via {MethodResolver}. `only:` / `except:` are recovered
  # best-effort by re-parsing the controller's own source file for literal
  # `before_action :name, only: [...]` / `except: [...]` declarations.
  class BeforeActionResolver
    def initialize(method_resolver:, locator: SourceLocator.new)
      @method_resolver = method_resolver
      @locator = locator
    end

    # Returns an Array<BeforeActionCallback> for the controller class.
    # Returns [] when the class cannot be loaded or has no callback chain.
    def resolve(controller_class)
      return [] if controller_class.nil?
      return [] unless controller_class.respond_to?(:_process_action_callbacks)

      chain = controller_class._process_action_callbacks
      filters = own_source_filters(controller_class)

      chain.filter_map { |callback| build_callback(callback, controller_class, filters) }
    rescue StandardError
      []
    end

    private

    def build_callback(callback, controller_class, filters)
      return nil unless callback.kind == :before

      filter = callback.filter
      return nil unless filter.is_a?(Symbol) || filter.is_a?(String)

      resolved = @method_resolver.resolve(controller_class, filter.to_sym)
      return nil if resolved.nil?

      own_only, own_except = filters[filter.to_s]
      BeforeActionCallback.new(
        method_name: filter.to_s, method_node: resolved.node,
        only: own_only, except: own_except
      )
    end

    # Parses the controller's own source file for `before_action :name,
    # only: [...]` / `except: [...]` declarations and returns a Hash of
    # name → [only_set_or_nil, except_set_or_nil].
    def own_source_filters(controller_class)
      file = own_source_file(controller_class)
      return {} if file.nil?

      sexp = Ripper.sexp(File.read(file))
      return {} if sexp.nil?

      filters = {}
      collect_filters(sexp, filters)
      filters
    rescue StandardError
      {}
    end

    def own_source_file(controller_class)
      methods = controller_class.instance_methods(false) + controller_class.private_instance_methods(false)
      methods.filter_map { |name| controller_class.instance_method(name).source_location&.first }.first
    rescue StandardError
      nil
    end

    def collect_filters(node, filters)
      return unless node.is_a?(Array)

      args = before_action_args(node)
      record_filter(args, filters) if args

      node.each { |child| collect_filters(child, filters) }
    end

    # Returns the argument-array node for a `before_action ...` command,
    # or nil for any other node.
    def before_action_args(node)
      return nil unless node[0] == :command
      return nil unless node[1].is_a?(Array) && node[1][0] == :@ident && node[1][1] == "before_action"

      args = node[2]
      args.is_a?(Array) && args[0] == :args_add_block ? Array(args[1]) : nil
    end

    def record_filter(args, filters)
      options = options_hash(args)
      args.each do |arg|
        name = symbol_or_string_value(arg)
        next unless name

        only = literal_action_set(options[:only])
        except = literal_action_set(options[:except])
        filters[name] = [only, except] unless filters.key?(name) && filters[name] != [nil, nil]
        filters[name] ||= [only, except]
      end
    end

    def options_hash(args)
      hash_arg = args.find { |arg| arg.is_a?(Array) && arg[0] == :bare_assoc_hash }
      return {} unless hash_arg

      evaluated = LiteralEvaluator.evaluate(hash_arg)
      evaluated.is_a?(Hash) ? evaluated : {}
    end

    def symbol_or_string_value(node)
      value = LiteralEvaluator.evaluate(node)
      case value
      when Symbol then value.to_s
      when String then value
      end
    end

    def literal_action_set(value)
      case value
      when Array
        names = value.filter_map { |element| element.is_a?(Symbol) || element.is_a?(String) ? element.to_s : nil }
        names.empty? ? nil : Set.new(names)
      when Symbol, String
        Set.new([value.to_s])
      end
    end
  end
end
