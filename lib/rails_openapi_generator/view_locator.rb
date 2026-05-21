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
    # `format_hint` (feature 011) restricts the lookup: `:json` → only
    # `.json.jbuilder` candidates; `:html` → only `.html.*` candidates; an
    # Array<Symbol> → try each format in order; nil → today's "prefer JSON"
    # lookup applies.
    def locate_view(route, template_name = nil, format_hint: nil)
      return nil if @views_root.nil?

      candidate_names(route, template_name).each do |name|
        match = match_view(name, format_hint: format_hint)
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

    # Returns a {ViewMatch} for `name`, honoring an optional `format_hint`.
    # When `format_hint` is nil, prefers a JSON view over an HTML view
    # (today's behavior). When `:json` or `:html`, restricts the lookup to
    # that format. When an Array, tries each format in order.
    def match_view(name, format_hint: nil)
      formats = Array(format_hint).compact
      formats = %i[json html] if formats.empty?

      formats.each do |format|
        match = lookup(name, format)
        return match if match
      end
      nil
    end

    def lookup(name, format)
      case format
      when :json
        path = File.join(@views_root, "#{name}#{JBUILDER_EXTENSION}")
        ViewMatch.new(kind: :json, path: path, name: name) if File.file?(path)
      when :html
        path = Dir.glob(File.join(@views_root, "#{name}.html.*")).min
        ViewMatch.new(kind: :html, path: path, name: name) if path
      end
    end
  end
end
