# frozen_string_literal: true

RSpec.describe "Resilience when a response shape cannot be determined", :rails_app do
  let(:generator) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/response_resilience.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config)
  end

  let(:document) { generator.document }
  let(:report)   { generator.generate }

  after { FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__)) }

  it "still gives an undeterminable endpoint a valid success response" do
    operation = document["paths"]["/api/posts"]["get"]

    expect(operation["responses"]).to have_key("200")
    expect(operation["responses"]["200"]).not_to have_key("content")
  end

  it "keeps the document valid with an undeterminable endpoint present" do
    expect(document).to be_a_valid_openapi_document
  end

  it "does NOT emit a 'response shape could not be determined' warning for a no-signal action (feature 015)" do
    # An action with no render, no view, no redirect, no respond_to,
    # and no contributing extras is documented as a body-less response
    # at the convention status (existing behavior) — but the warning
    # channel no longer fires, since Rails returns an implicit empty
    # response for these actions at runtime.
    expect(report.warnings.join("\n")).not_to match(%r{/api/posts: response shape could not be determined})
  end

  it "preserves the byte-identical OpenAPI shape for the no-signal endpoint" do
    responses = document["paths"]["/api/posts"]["get"]["responses"]
    expect(responses.keys).to eq(["200"])
    expect(responses["200"]).not_to have_key("content")
  end

  it "leaves other endpoints' response bodies unaffected" do
    body = document.dig("paths", "/api/users", "get", "responses", "200", "content", "application/json", "schema")
    expect(body["type"]).to eq("array")
  end

  it "completes the run successfully" do
    expect(report.success?).to be(true)
  end
end
