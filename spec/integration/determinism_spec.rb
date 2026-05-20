# frozen_string_literal: true

require "json"

RSpec.describe "Deterministic output", :rails_app do
  it "produces byte-identical output across runs of unchanged input (SC-008)" do
    paths = Array.new(2) do |index|
      output = File.expand_path("../../tmp/spec/determinism_#{index}.json", __dir__)
      config = RailsOpenapiGenerator::Configuration.new
      config.output_path = output
      RailsOpenapiGenerator::Generator.new(config).generate
      output
    end

    expect(File.read(paths[0])).to eq(File.read(paths[1]))
  ensure
    FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__))
  end

  it "orders response body schema properties deterministically (FR-010)" do
    schemas = Array.new(2) do
      config = RailsOpenapiGenerator::Configuration.new
      config.output_path = File.expand_path("../../tmp/spec/det_response.json", __dir__)
      document = RailsOpenapiGenerator::Generator.new(config).document
      document.dig("paths", "/api/users/{id}", "get", "responses", "200",
                   "content", "application/json", "schema", "properties").keys
    end

    expect(schemas[0]).to eq(schemas[1])
    expect(schemas[0]).to eq(schemas[0].sort)
  ensure
    FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__))
  end

  it "produces stable non-JSON marks (content type, tags, extensions) across runs (FR-012)" do
    operations = Array.new(2) do
      config = RailsOpenapiGenerator::Configuration.new
      config.output_path = File.expand_path("../../tmp/spec/det_html.json", __dir__)
      RailsOpenapiGenerator::Generator.new(config).document["paths"]["/api/pages/{id}"]["get"]
    end

    expect(operations[0]).to eq(operations[1])
  ensure
    FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__))
  end

  it "produces a stable wrapper-resolved download operation across runs (FR-011)" do
    operations = Array.new(2) do
      config = RailsOpenapiGenerator::Configuration.new
      config.output_path = File.expand_path("../../tmp/spec/det_wrapper.json", __dir__)
      RailsOpenapiGenerator::Generator.new(config).document["paths"]["/api/reports/chained"]["get"]
    end

    expect(operations[0]).to eq(operations[1])
  ensure
    FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__))
  end

  it "produces a stable explicit-status response across runs (FR-011)" do
    responses = Array.new(2) do
      config = RailsOpenapiGenerator::Configuration.new
      config.output_path = File.expand_path("../../tmp/spec/det_status.json", __dir__)
      RailsOpenapiGenerator::Generator.new(config).document["paths"]["/api/statuses/make"]["post"]["responses"]
    end

    expect(responses[0]).to eq(responses[1])
  ensure
    FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__))
  end

  it "produces stable template-render output across runs (feature 011)" do
    operations = Array.new(2) do
      config = RailsOpenapiGenerator::Configuration.new
      config.output_path = File.expand_path("../../tmp/spec/det_template.json", __dir__)
      RailsOpenapiGenerator::Generator.new(config).document["paths"]["/api/template_renders/update"]["put"]
    end

    expect(operations[0]).to eq(operations[1])
  ensure
    FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__))
  end

  it "produces a stable multi-status oneOf list across runs (FR-013)" do
    schemas = Array.new(2) do
      config = RailsOpenapiGenerator::Configuration.new
      config.output_path = File.expand_path("../../tmp/spec/det_multi_status.json", __dir__)
      doc = RailsOpenapiGenerator::Generator.new(config).document
      doc["paths"]["/api/multi_status/dup_distinct"]["post"]["responses"]["201"]
        .dig("content", "application/json", "schema", "oneOf")
    end

    expect(schemas[0]).to eq(schemas[1])
    expect(schemas[0]).to eq(schemas[0].sort_by { |s| JSON.generate(s) })
  ensure
    FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__))
  end

  it "produces a stable redirect response across runs (FR-011)" do
    responses = Array.new(2) do
      config = RailsOpenapiGenerator::Configuration.new
      config.output_path = File.expand_path("../../tmp/spec/det_redirect.json", __dir__)
      RailsOpenapiGenerator::Generator.new(config).document["paths"]["/api/redirects/create"]["post"]["responses"]
    end

    expect(responses[0]).to eq(responses[1])
  ensure
    FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__))
  end

  it "emits implicit parameters in a stable order across runs (FR-011)" do
    bodies = Array.new(2) do
      config = RailsOpenapiGenerator::Configuration.new
      config.output_path = File.expand_path("../../tmp/spec/det_implicit.json", __dir__)
      RailsOpenapiGenerator::Generator.new(config)
                                      .document["paths"]["/api/inputs"]["post"]
                                      .dig("requestBody", "content", "application/json", "schema", "properties").keys
    end

    expect(bodies[0]).to eq(bodies[1])
    expect(bodies[0]).to eq(bodies[0].sort)
  ensure
    FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__))
  end
end
