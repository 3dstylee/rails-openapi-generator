# frozen_string_literal: true

require "benchmark"

RSpec.describe "Generation performance", :rails_app do
  let(:generator) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/performance.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config)
  end

  after do
    Rails.application.reload_routes!
    FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__))
  end

  it "generates a document for ~200 routes in under 5 seconds" do
    Rails.application.routes.draw do
      200.times { |index| get "/perf/resource_#{index}", to: "api/posts#index" }
    end

    document = nil
    elapsed = Benchmark.realtime { document = generator.document }

    expect(document["paths"].size).to be >= 200
    expect(elapsed).to be < 5.0
  end
end
