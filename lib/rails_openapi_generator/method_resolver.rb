# frozen_string_literal: true

module RailsOpenapiGenerator
  # The located definition of a method reached during wrapper resolution.
  ResolvedMethod = Struct.new(:name, :node, :location, keyword_init: true)

  # Locates the definition of a method called (with no explicit receiver) inside
  # a controller. Resolution delegates to Ruby's own method lookup —
  # `Module#instance_method(...).source_location` performs the full ancestor /
  # included-module / parent-controller resolution — then the file is parsed for
  # the method's AST. Methods defined outside the host application, or with no
  # source location, are unresolvable.
  class MethodResolver
    def initialize(yard_parser: YardParser.new, app_root: nil)
      @yard_parser = yard_parser
      @app_root = app_root || default_app_root
    end

    # Returns a {ResolvedMethod} for `(controller_class, method_name)`, or nil
    # when the method cannot be located within the application.
    def resolve(controller_class, method_name)
      return nil if controller_class.nil? || method_name.nil?

      unbound = unbound_method(controller_class, method_name)
      return nil if unbound.nil?

      file, line = unbound.source_location
      return nil if file.nil? || !app_file?(file) || !File.file?(file)

      node = method_node(file, method_name.to_s)
      node && ResolvedMethod.new(name: method_name.to_s, node: node, location: "#{file}:#{line}")
    end

    private

    def default_app_root
      return nil unless defined?(Rails) && Rails.respond_to?(:root) && Rails.root

      Rails.root.to_s
    rescue StandardError
      nil
    end

    def unbound_method(controller_class, method_name)
      controller_class.instance_method(method_name)
    rescue NameError
      nil
    end

    # Only methods defined inside the application are followed; a method that
    # resolves into a gem or the framework is treated as unresolvable.
    def app_file?(file)
      return false if @app_root.nil?

      file.start_with?("#{@app_root}/")
    end

    def method_node(file, method_name)
      @yard_parser.parse(file)[method_name]&.method_node
    rescue StandardError
      nil
    end
  end
end
