# frozen_string_literal: true

RSpec.describe "Helper argument propagation (feature 018)", :rails_app do
  let(:document) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/feature_018.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config).document
  end

  def responses_for(path, method)
    document["paths"][path][method]["responses"]
  end

  describe "US1: positional argument binding from a rescue clause" do
    it "documents the 422 entry from render_error called with literal status" do
      responses = responses_for("/api/binding_helpers/create", "post")
      expect(responses).to have_key("422")
    end

    it "carries the literal-hash body schema for the 422 entry" do
      schema = responses_for("/api/binding_helpers/create", "post")["422"]["content"]["application/json"]["schema"]
      expect(schema["properties"]).to include("response", "status_code")
      # status_code was 422 literal at the call site → typed in the helper render's hash.
      expect(schema["properties"]["status_code"]).to eq("type" => "integer")
    end

    it "preserves the happy-path entry from render_success" do
      responses = responses_for("/api/binding_helpers/create", "post")
      expect(responses).to have_key("200")
    end
  end

  describe "US2: multi-level helper propagation" do
    it "documents the 200 entry from inner_helper's head bound through outer_helper" do
      responses = responses_for("/api/binding_helpers/chain", "get")
      expect(responses).to have_key("200")
      expect(responses["200"]).not_to have_key("content")
    end
  end

  describe "US3: keyword argument binding" do
    it "documents the 202 entry from `respond(json:, status:)`" do
      responses = responses_for("/api/binding_helpers/kwargs", "get")
      expect(responses).to have_key("202")
    end

    it "carries the literal kwarg hash as the body schema" do
      schema = responses_for("/api/binding_helpers/kwargs", "get")["202"]["content"]["application/json"]["schema"]
      expect(schema["properties"]["ok"]).to eq("type" => "boolean")
    end
  end

  it "produces a valid OpenAPI document" do
    expect(document).to be_a_valid_openapi_document
  end
end
