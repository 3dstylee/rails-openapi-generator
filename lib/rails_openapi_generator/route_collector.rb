# frozen_string_literal: true

module RailsOpenapiGenerator
  # Discovers endpoints from the Rails route set and applies the configured filter.
  class RouteCollector
    HTTP_METHODS = %w[GET POST PUT PATCH DELETE].freeze

    def initialize(rails_app: nil, route_filter: nil)
      @rails_app    = rails_app || default_rails_app
      @route_filter = route_filter
    end

    # Returns the discovered {Route}s in a deterministic order.
    def collect
      routes = []

      @rails_app.routes.routes.each do |rails_route|
        verbs_for(rails_route).each do |verb|
          route = build_route(rails_route, verb)
          next if route.nil?
          next if @route_filter && !@route_filter.call(route)

          routes << route
        end
      end

      routes.sort_by { |route| [route.path, route.http_method] }
    end

    private

    def default_rails_app
      raise ConfigurationError, "Rails application is not loaded" unless defined?(Rails) && Rails.application

      Rails.application
    end

    def build_route(rails_route, verb)
      path       = normalize_path(rails_route.path.spec.to_s)
      controller = rails_route.defaults[:controller]
      action     = rails_route.defaults[:action]
      external   = controller.nil? || action.nil?

      Route.new(http_method: verb, path: path, controller: controller, action: action, external: external)
    end

    # A Rails route's verb may be a String or a Regexp; yield only recognized HTTP methods.
    def verbs_for(rails_route)
      verb = rails_route.verb
      verb = verb.source if verb.is_a?(Regexp)
      verb.to_s.upcase.scan(/[A-Z]+/).select { |candidate| HTTP_METHODS.include?(candidate) }.uniq
    end

    # Strips Rails' optional format suffix and surrounding optional-segment parentheses.
    def normalize_path(spec)
      spec.sub(/\(\.:format\)\z/, "").gsub(/[()]/, "")
    end
  end
end
