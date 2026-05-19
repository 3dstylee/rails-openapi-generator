# frozen_string_literal: true

module RailsOpenapiGenerator
  # Orchestrates the pipeline: routes -> operations -> OpenAPI document -> file.
  class Generator
    def initialize(configuration = RailsOpenapiGenerator.configuration)
      @configuration = configuration
    end

    # Builds the document, writes it, and returns a {GenerationReport}.
    def generate
      @configuration.validate!
      document = build_document
      @report.output_path = Writer.new(@configuration).write(document)
      @report
    end

    # Builds and returns the OpenAPI document Hash without writing a file.
    def document
      @configuration.validate!
      build_document
    end

    private

    def build_document
      @report = GenerationReport.new
      setup_pipeline
      endpoints = routes_to_process.filter_map { |route| build_endpoint(route) }
      DocumentBuilder.new(@configuration).build(endpoints)
    end

    def setup_pipeline
      views_root = views_root_path
      @locator          = SourceLocator.new
      @parser           = YardParser.new
      @param_extractor  = ParamExtractor.new
      @doc_extractor    = DocCommentExtractor.new
      @render_extractor = RenderExtractor.new
      @view_locator     = ViewLocator.new(views_root: views_root)
      @jbuilder_parser  = JbuilderParser.new(views_root: views_root)
      @method_resolver  = MethodResolver.new(yard_parser: @parser)
      @walker           = ControllerMethodWalker.new(
        method_resolver: @method_resolver, max_depth: @configuration.method_resolution_depth
      )
      @wrapper_resolver = WrapperDownloadResolver.new(walker: @walker)
      @implicit_scanner = ImplicitParamScanner.new(walker: @walker)
      @classifier       = RenderClassifier.new(view_locator: @view_locator, wrapper_resolver: @wrapper_resolver)
      @response_builder = ResponseBuilder.new
      @operation_builder = OperationBuilder.new
    end

    def routes_to_process
      RouteCollector.new(route_filter: @configuration.route_filter).collect.filter_map do |route|
        if route.resolvable?
          route
        else
          @report.skip(route, "no backing controller action")
          nil
        end
      end
    end

    def build_endpoint(route)
      file             = locate_source(route)
      action_source    = file && @parser.parse(file)[route.action]
      action_node      = action_source&.method_node
      controller_class = @locator.controller_class(route)
      param_calls      = @param_extractor.extract(action_source)
      warn_unresolved(route, param_calls)

      response = build_response(route, action_source, controller_class)
      count_kind(response)
      endpoint = @operation_builder.build(
        route,
        doc_comment: @doc_extractor.extract(action_source),
        param_calls: param_calls,
        source_location: source_location_for(file, action_source),
        response: response,
        implicit_params: @implicit_scanner.scan(controller_class, action_node)
      )
      @report.processed_count += 1
      endpoint
    rescue StandardError => e
      @report.warn("#{route.http_method} #{route.path}: #{e.message}")
      @report.processed_count += 1
      @operation_builder.build(route)
    end

    def build_response(route, action_source, controller_class)
      render_result  = @render_extractor.extract(action_source)
      classification = @classifier.classify(
        route, render_result,
        controller_class: controller_class,
        action_node: action_source&.method_node
      )
      view_schema    = classification.jbuilder_file ? @jbuilder_parser.parse(classification.jbuilder_file) : nil
      response       = @response_builder.build(route, classification: classification, view_schema: view_schema)

      if response.undeterminable?
        @report.warn("#{route.http_method} #{route.path}: response shape could not be determined")
      end
      response
    end

    def count_kind(response)
      @report.html_page_count += 1 if response.kind == :html_page
      @report.file_download_count += 1 if response.kind == :file_download
    end

    def locate_source(route)
      file = @locator.locate(route)
      @report.warn("#{route.http_method} #{route.path}: controller source not found") if file.nil?
      file
    end

    def views_root_path
      return nil unless defined?(Rails) && Rails.respond_to?(:root) && Rails.root

      File.join(Rails.root.to_s, "app", "views")
    rescue StandardError
      nil
    end

    # A "path:line" reference (relative to the Rails root) to the action's source.
    def source_location_for(file, action_source)
      return nil if file.nil?

      relative = relative_path(file)
      line = action_source&.line
      line ? "#{relative}:#{line}" : relative
    end

    def relative_path(file)
      root = (Rails.root.to_s if defined?(Rails) && Rails.respond_to?(:root) && Rails.root)
      root && file.start_with?("#{root}/") ? file.delete_prefix("#{root}/") : file
    end

    def warn_unresolved(route, param_calls)
      param_calls.reject(&:fully_resolved?).each do |call|
        name = call.name || "a parameter"
        @report.warn("#{route.http_method} #{route.path}: non-literal param! arguments for #{name}")
      end
    end
  end
end
