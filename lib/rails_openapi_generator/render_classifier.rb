# frozen_string_literal: true

module RailsOpenapiGenerator
  # The outcome of classifying one action's response.
  #
  # `kind` is `:json`, `:html_page`, `:file_download`, or `:undeterminable`.
  # `jbuilder_file` is set for a JSON endpoint resolved via a view template;
  # `template_name` is set for an HTML-page endpoint resolved via a view.
  Classification = Struct.new(:kind, :render_result, :jbuilder_file, :template_name, keyword_init: true)

  # Decides whether an action returns JSON, renders an HTML page, sends a file
  # download, or is undeterminable — by static signals only (research R3).
  # When no direct signal classifies the action, a {WrapperDownloadResolver}
  # (when supplied) is consulted to detect a download made through wrappers.
  class RenderClassifier
    def initialize(view_locator:, wrapper_resolver: nil)
      @view_locator = view_locator
      @wrapper_resolver = wrapper_resolver
    end

    # Returns a {Classification} for the route given its {RenderResult}.
    # `controller_class` and `action_node` enable wrapper-download resolution.
    def classify(route, render_result, controller_class: nil, action_node: nil)
      # Precedence: JSON render > send_file > render html: > view lookup.
      return classification(:json, render_result) if render_result.renders_json
      return classification(:file_download, render_result) if render_result.file_download
      return classification(:html_page, render_result) if render_result.html_inline

      classify_by_view(route, render_result, controller_class, action_node)
    end

    private

    def classify_by_view(route, render_result, controller_class, action_node)
      view = @view_locator.locate_view(route, render_result.template)

      case view&.kind
      when :json
        classification(:json, render_result, jbuilder_file: view.path)
      when :html
        classification(:html_page, render_result, template_name: view.name)
      else
        classify_by_wrapper(render_result, controller_class, action_node)
      end
    end

    # Last resort: a download reached through wrapper methods.
    def classify_by_wrapper(render_result, controller_class, action_node)
      if @wrapper_resolver&.download?(controller_class, action_node)
        classification(:file_download, render_result)
      else
        classification(:undeterminable, render_result)
      end
    end

    def classification(kind, render_result, jbuilder_file: nil, template_name: nil)
      Classification.new(
        kind: kind, render_result: render_result,
        jbuilder_file: jbuilder_file, template_name: template_name
      )
    end
  end
end
