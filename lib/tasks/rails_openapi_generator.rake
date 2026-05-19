# frozen_string_literal: true

namespace :openapi do
  desc "Generate an OpenAPI document for all application endpoints"
  task generate: :environment do
    configuration = RailsOpenapiGenerator.configuration
    configuration.output_path = ENV["OUTPUT"] if ENV["OUTPUT"]
    configuration.format      = ENV["FORMAT"].to_sym if ENV["FORMAT"]

    report = RailsOpenapiGenerator::Generator.new(configuration).generate
    puts report.summary
  end
end
