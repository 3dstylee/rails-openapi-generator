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
      endpoints = collect_endpoints
      DocumentBuilder.new(@configuration).build(endpoints)
    end

    def collect_endpoints
      locator         = SourceLocator.new
      parser          = YardParser.new
      param_extractor = ParamExtractor.new
      doc_extractor   = DocCommentExtractor.new
      operation_builder = OperationBuilder.new

      routes_to_process.filter_map do |route|
        build_endpoint(route, locator, parser, param_extractor, doc_extractor, operation_builder)
      end
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

    def build_endpoint(route, locator, parser, param_extractor, doc_extractor, operation_builder)
      file          = locate_source(route, locator)
      action_source = file && parser.parse(file)[route.action]
      param_calls   = param_extractor.extract(action_source)
      warn_unresolved(route, param_calls)
      doc_comment = doc_extractor.extract(action_source)

      endpoint = operation_builder.build(
        route,
        doc_comment: doc_comment,
        param_calls: param_calls,
        source_location: source_location_for(file, action_source)
      )
      @report.processed_count += 1
      endpoint
    rescue StandardError => e
      @report.warn("#{route.http_method} #{route.path}: #{e.message}")
      @report.processed_count += 1
      operation_builder.build(route)
    end

    def locate_source(route, locator)
      file = locator.locate(route)
      @report.warn("#{route.http_method} #{route.path}: controller source not found") if file.nil?
      file
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
