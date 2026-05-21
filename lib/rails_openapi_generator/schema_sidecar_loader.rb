# frozen_string_literal: true

require "json"

module RailsOpenapiGenerator
  # Loads JSON Schema sidecar files that sit next to jbuilder templates
  # or at the conventional view path for an action. The sidecar's
  # contents are returned verbatim as the OpenAPI body schema, replacing
  # the parser's inference.
  #
  # Two lookup modes:
  #   - {#for_jbuilder}: sibling of a `.json.jbuilder` template.
  #     `app/views/api/users/_user.json.jbuilder`
  #     → `app/views/api/users/_user.schema.json`
  #   - {#for_view}: action's conventional view path.
  #     `(views_root, "api/users", "show")`
  #     → `<views_root>/api/users/show.schema.json`
  #
  # Malformed sidecars (invalid JSON) emit a warning via the optional
  # `report` collaborator and fall back to nil so the caller uses its
  # inferred schema. Lookups are cached for the loader's lifetime.
  class SchemaSidecarLoader
    JBUILDER_EXTENSION = ".json.jbuilder"
    SIDECAR_EXTENSION  = ".schema.json"

    def initialize(report: nil)
      @report = report
      @cache  = {}
    end

    # Returns the sidecar schema Hash for a jbuilder template path, or
    # nil when no sidecar exists at the sibling location.
    def for_jbuilder(jbuilder_path)
      return nil if jbuilder_path.nil? || !jbuilder_path.end_with?(JBUILDER_EXTENSION)

      load_path(sibling_sidecar_path(jbuilder_path))
    end

    # Returns the sidecar schema Hash for an action's conventional view
    # path (`<views_root>/<controller>/<action>.schema.json`), or nil
    # when no sidecar exists.
    def for_view(views_root, controller, action)
      return nil if views_root.nil? || controller.nil? || action.nil?

      load_path(File.join(views_root, "#{controller}/#{action}#{SIDECAR_EXTENSION}"))
    end

    private

    def sibling_sidecar_path(jbuilder_path)
      jbuilder_path.sub(/#{Regexp.escape(JBUILDER_EXTENSION)}\z/, SIDECAR_EXTENSION)
    end

    def load_path(path)
      return nil if path.nil? || !File.file?(path)
      return @cache[path] if @cache.key?(path)

      @cache[path] = parse_sidecar(path)
    end

    def parse_sidecar(path)
      JSON.parse(File.read(path))
    rescue JSON::ParserError => e
      @report&.warn("schema sidecar `#{path}` failed to parse: #{e.message}")
      nil
    end
  end
end
