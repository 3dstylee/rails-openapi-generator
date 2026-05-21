# frozen_string_literal: true

RSpec.describe "JSON Schema sidecar files (feature 020)", :rails_app do
  let(:generator) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/feature_020.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config)
  end

  let(:document) { generator.document }
  let(:report)   { generator.generate }

  after { FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__)) }

  def schema_at(path, method, status: "200")
    document["paths"][path][method]["responses"][status]["content"]["application/json"]["schema"]
  end

  describe "US1: partial sidecar overrides the parser's inference" do
    it "uses the sidecar's typed properties for `json.user partial:` (single object form)" do
      body = schema_at("/api/sidecars/with_partial", "get")
      user = body["properties"]["user"]
      expect(user["type"]).to eq("object")
      expect(user["properties"]["email"]).to include("type" => "string", "format" => "email")
      expect(user["required"]).to contain_exactly("id", "name", "email")
    end

    it "uses the sidecar for the array `partial:` form (items get the typed shape)" do
      body = schema_at("/api/sidecars/with_partial", "get")
      items = body["properties"]["users"]["items"]
      expect(items["properties"]["id"]).to include("type" => "integer", "minimum" => 1)
      expect(items["properties"]["name"]).to include("type" => "string", "minLength" => 1)
    end
  end

  describe "US2: action sidecar overrides the action's inferred body" do
    it "overrides an inline `render json:` body schema" do
      body = schema_at("/api/sidecars/inline_render", "get")
      # The inline render has `{ status: "ok" }` (just `status`), but
      # the sidecar declares both `status` (with enum) and a nested
      # `metadata` object. The sidecar wins.
      expect(body["properties"].keys).to contain_exactly("status", "metadata")
      expect(body["properties"]["status"]["enum"]).to eq(%w[ok pending error])
      expect(body["properties"]["metadata"]["properties"]).to have_key("request_id")
    end

    it "documents a response for an action with NO view and NO inline render" do
      body = schema_at("/api/sidecars/no_view", "get")
      expect(body["properties"]).to include("ok", "ran_at")
      expect(body["properties"]["ran_at"]["format"]).to eq("date-time")
    end
  end

  describe "US3: malformed sidecar resilience" do
    it "emits a warning naming the malformed file" do
      expect(report.warnings.join("\n")).to match(/malformed\.schema\.json.*failed to parse/)
    end

    it "falls back to the action's inferred body when the sidecar is malformed" do
      body = schema_at("/api/sidecars/malformed", "get")
      expect(body["properties"]["ok"]).to eq("type" => "boolean", "example" => true)
    end

    it "does not raise during document generation" do
      expect { document }.not_to raise_error
    end
  end

  it "produces a valid OpenAPI document" do
    expect(document).to be_a_valid_openapi_document
  end
end
