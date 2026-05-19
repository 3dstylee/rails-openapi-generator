# frozen_string_literal: true

module RailsOpenapiGenerator
  # A resolved view file for an action, with its kind.
  ViewMatch = Struct.new(:kind, :path, :name, keyword_init: true)

  # Resolves a route — and an optional explicitly rendered template name — to a
  # view file, reporting whether it is a JSON (`.json.jbuilder`) or HTML
  # (`.html.*`) view. Resolution is by file existence only; no code runs.
  class ViewLocator
    JBUILDER_EXTENSION = ".json.jbuilder"

    def initialize(views_root: nil)
      @views_root = views_root || default_views_root
    end

    # Returns a {ViewMatch} for the action, or nil when no view is found.
    # `template_name` is an explicitly rendered template (from `RenderResult`).
    def locate_view(route, template_name = nil)
      return nil if @views_root.nil?

      candidate_names(route, template_name).each do |name|
        match = match_view(name)
        return match if match
      end
      nil
    end

    private

    def default_views_root
      return nil unless defined?(Rails) && Rails.respond_to?(:root) && Rails.root

      File.join(Rails.root.to_s, "app", "views")
    rescue StandardError
      nil
    end

    def candidate_names(route, template_name)
      names = []
      names << expand(template_name, route) if template_name
      names << File.join(route.controller, route.action) if route.controller && route.action
      names
    end

    # A bare template name is resolved relative to the controller's view dir;
    # a slash-qualified name is used as an absolute view path.
    def expand(template_name, route)
      return template_name if template_name.include?("/") || route.controller.nil?

      File.join(route.controller, template_name)
    end

    # Prefers a JSON view over an HTML view for the same logical name.
    def match_view(name)
      jbuilder = File.join(@views_root, "#{name}#{JBUILDER_EXTENSION}")
      return ViewMatch.new(kind: :json, path: jbuilder, name: name) if File.file?(jbuilder)

      html = Dir.glob(File.join(@views_root, "#{name}.html.*")).min
      return ViewMatch.new(kind: :html, path: html, name: name) if html

      nil
    end
  end
end
