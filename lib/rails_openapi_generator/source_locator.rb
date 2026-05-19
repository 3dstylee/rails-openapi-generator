# frozen_string_literal: true

module RailsOpenapiGenerator
  # Resolves a {Route} to the source file of its controller, without executing any action.
  class SourceLocator
    # Returns the absolute controller source file path, or nil when it cannot be resolved.
    def locate(route)
      class_name = route.controller_class_name
      return nil if class_name.nil?

      klass = constantize(class_name)
      return nil if klass.nil?

      location = source_location_for(klass, class_name)
      location && File.exist?(location) ? location : nil
    end

    # Returns the resolved controller Class for a route, or nil. Used by wrapper
    # resolution, which needs the live class for Ruby method lookup.
    def controller_class(route)
      class_name = route.controller_class_name
      class_name && constantize(class_name)
    end

    private

    def constantize(class_name)
      class_name.split("::").inject(Object) do |namespace, const|
        namespace.const_get(const)
      end
    rescue NameError
      nil
    end

    def source_location_for(klass, class_name)
      if Object.respond_to?(:const_source_location)
        Object.const_source_location(class_name)&.first
      else
        klass.instance_methods(false).filter_map { |m| klass.instance_method(m).source_location&.first }.first
      end
    rescue StandardError
      nil
    end
  end
end
