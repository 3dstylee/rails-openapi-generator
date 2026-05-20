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

  it "produces stable nested param! block output across runs (feature 008)" do
    operations = Array.new(2) do
      config = RailsOpenapiGenerator::Configuration.new
      config.output_path = File.expand_path("../../tmp/spec/det_nested_params.json", __dir__)
      RailsOpenapiGenerator::Generator.new(config).document["paths"]["/api/nested_params/search"]["post"]
    end

    expect(operations[0]).to eq(operations[1])
  ensure
    FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__))
  end

  it "produces a stable resolved-constant enum across runs (feature 013)" do
    enums = Array.new(2) do
      config = RailsOpenapiGenerator::Configuration.new
      config.output_path = File.expand_path("../../tmp/spec/det_constants.json", __dir__)
      op = RailsOpenapiGenerator::Generator.new(config)
                                           .document["paths"]["/api/constant_references/execute"]["post"]
      mood = op.dig("requestBody", "content", "application/json", "schema", "properties", "mood")
      mood["enum"]
    end

    expect(enums[0]).to eq(enums[1])
    expect(enums[0]).to eq(%w[modern classic minimalist scandinavian industrial])
  ensure
    FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__))
  end

  it "produces a stable multi-content-type response across runs (feature 012)" do
    contents = Array.new(2) do
      config = RailsOpenapiGenerator::Configuration.new
      config.output_path = File.expand_path("../../tmp/spec/det_respond_to.json", __dir__)
      doc = RailsOpenapiGenerator::Generator.new(config).document
      doc["paths"]["/api/respond_to/index"]["get"]["responses"]["200"]["content"]
    end

    expect(contents[0]).to eq(contents[1])
    expect(contents[0].keys).to eq(contents[0].keys.sort)
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

  it "produces stable resolved-partial sibling-key schemas across runs (feature 016)" do
    bodies = Array.new(2) do
      config = RailsOpenapiGenerator::Configuration.new
      config.output_path = File.expand_path("../../tmp/spec/det_partials.json", __dir__)
      RailsOpenapiGenerator::Generator.new(config)
                                      .document["paths"]["/api/activity_logs"]["get"]["responses"]["200"]
                                      .dig("content", "application/json", "schema")
    end

    expect(bodies[0]).to eq(bodies[1])
    items = bodies[0]["properties"].values.map { |entry| entry["items"] }
    expect(items.uniq.size).to eq(1)
  ensure
    FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__))
  end

  it "produces a stable case/when merge order across runs (feature 016)" do
    bodies = Array.new(2) do
      config = RailsOpenapiGenerator::Configuration.new
      config.output_path = File.expand_path("../../tmp/spec/det_case.json", __dir__)
      RailsOpenapiGenerator::Generator.new(config)
                                      .document["paths"]["/api/case_branches/show"]["get"]["responses"]["200"]
                                      .dig("content", "application/json", "schema", "properties").keys
    end

    expect(bodies[0]).to eq(bodies[1])
    expect(bodies[0]).to eq(bodies[0].sort)
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
