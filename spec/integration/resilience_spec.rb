# frozen_string_literal: true

RSpec.describe "Resilience to endpoints that cannot be analyzed", :rails_app do
  let(:generator) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/resilience.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config)
  end

  let(:document) { generator.document }
  let(:report)   { generator.generate }

  after { FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__)) }

  it "records a warning for a route whose controller cannot be analyzed (FR-016)" do
    expect(report.warnings.join("\n")).to match(%r{/api/orphan})
  end

  it "still includes every other endpoint in the document (SC-006)" do
    expect(document["paths"].keys).to include("/api/users", "/api/posts", "/api/users/{id}")
  end

  it "still produces an operation for the un-analyzable route" do
    expect(document["paths"]).to have_key("/api/orphan")
  end

  it "completes the run successfully despite the warning" do
    expect(report.success?).to be(true)
  end
end
