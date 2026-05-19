# frozen_string_literal: true

module RailsOpenapiGenerator
  # A run summary: endpoints processed, routes skipped, and non-fatal warnings.
  class GenerationReport
    attr_accessor :processed_count, :output_path, :html_page_count, :file_download_count
    attr_reader :skipped, :warnings

    def initialize
      @processed_count     = 0
      @html_page_count     = 0
      @file_download_count = 0
      @skipped             = []
      @warnings            = []
      @output_path         = nil
    end

    # Records a route excluded from the document, with the reason.
    def skip(route, reason)
      @skipped << { route: route, reason: reason }
    end

    # Records a non-fatal issue; the run still completes.
    def warn(message)
      @warnings << message
    end

    # A run always completes (per-endpoint problems degrade to warnings).
    def success?
      true
    end

    # A human-readable summary printed by the rake task and CLI.
    def summary
      lines = []
      lines << "OpenAPI document written to #{output_path}" if output_path
      lines << "  Processed:      #{processed_count} endpoints"
      lines << "  HTML pages:     #{html_page_count} endpoints"
      lines << "  File downloads: #{file_download_count} endpoints"
      lines << "  Skipped:        #{skipped.size}"
      skipped.each do |entry|
        route = entry[:route]
        lines << "    - #{route.http_method} #{route.path} (#{entry[:reason]})"
      end
      lines << "  Warnings:       #{warnings.size}"
      warnings.each { |message| lines << "    - #{message}" }
      lines.join("\n")
    end
  end
end
