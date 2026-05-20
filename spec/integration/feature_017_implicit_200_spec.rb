# frozen_string_literal: true

RSpec.describe "Implicit happy-path entry with error extras (feature 017)", :rails_app do
  let(:document) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/feature_017.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config).document
  end

  let(:operation) { document["paths"].fetch("/api/silent_with_rescue")["get"] }
  let(:responses) { operation["responses"] }

  it "emits a 200 entry alongside the inherited rescue_from statuses" do
    expect(responses.keys).to include("200", "400", "403", "404", "422")
  end

  it "documents the 200 entry as body-less (Rails returns implicit empty response)" do
    expect(responses["200"]).not_to have_key("content")
  end

  it "leaves the rescue_from handler entries unchanged" do
    expect(responses["404"]["content"]["application/json"]["schema"]["properties"]).to have_key("error")
    expect(responses["422"]["content"]["application/json"]["schema"]["properties"]).to have_key("errors")
  end

  it "produces a valid OpenAPI document" do
    expect(document).to be_a_valid_openapi_document
  end
end
