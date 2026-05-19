# frozen_string_literal: true

module RailsOpenapiGenerator
  # A discovered mapping from the Rails route set: one HTTP method + path pair.
  class Route
    attr_reader :http_method, :path, :controller, :action, :path_params

    def initialize(http_method:, path:, controller:, action:, external: false)
      @http_method = http_method.to_s.upcase
      @path        = path
      @controller  = controller
      @action      = action
      @external    = external
      @path_params = path.scan(/[:*]([A-Za-z_][A-Za-z0-9_]*)/).flatten
    end

    # True for redirects / mounted engines that have no controller action to inspect.
    def external?
      @external
    end

    # True when the route maps to an inspectable controller action.
    def resolvable?
      !external? && !controller.nil? && !action.nil?
    end

    # The host controller class name, e.g. "Api::UsersController", or nil when unresolvable.
    def controller_class_name
      return nil if controller.nil?

      "#{controller.split("/").map { |s| camelize(s) }.join("::")}Controller"
    end

    private

    def camelize(string)
      string.split("_").map { |part| part.empty? ? part : part[0].upcase + part[1..] }.join
    end
  end
end
