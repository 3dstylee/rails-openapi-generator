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

  it "records a warning naming the endpoint with an undeterminable response" do
    expect(report.warnings.join("\n")).to match(%r{/api/posts: response shape could not be determined})
  end

  it "leaves other endpoints' response bodies unaffected" do
    body = document.dig("paths", "/api/users", "get", "responses", "200", "content", "application/json", "schema")
    expect(body["type"]).to eq("array")
  end

  it "completes the run successfully" do
    expect(report.success?).to be(true)
  end
end
