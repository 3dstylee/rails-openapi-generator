# frozen_string_literal: true

RSpec.describe "Auto-extract `example` from literal values (feature 021)", :rails_app do
  let(:document) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/feature_021.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config).document
  end

  def schema_at(path, method, status: "200")
    document["paths"][path][method]["responses"][status]["content"]["application/json"]["schema"]
  end

  describe "US1: primitive literals carry an example" do
    it "emits the literal string value as `example` on a `json.role \"member\"` property" do
      # api/users/_user.json.jbuilder has `json.role "member"`.
      body = schema_at("/api/users/{id}", "get")
      expect(body["properties"]["role"]).to eq("type" => "string", "example" => "member")
    end

    it "emits a literal integer as `example`" do
      # api/users/_user.json.jbuilder's partial → typed_user fixture (feature 020)
      # has `json.id 1; json.message "hello"; json.created_at "2026-01-01"` — see
      # the activity_logs partial which feeds /api/activity_logs.
      body = schema_at("/api/activity_logs", "get")
      items = body["properties"]["today_logs"]["items"]
      expect(items["properties"]["id"]).to eq("type" => "integer", "example" => 1)
      expect(items["properties"]["message"]).to eq("type" => "string", "example" => "hello")
    end

    it "emits a literal boolean as `example` on an inline `render json:` body" do
      # api/users#post renders `render json: { id: 1, role: "member", active: true }`.
      body = document["paths"]["/api/users"]["post"]["responses"]["201"]["content"]["application/json"]["schema"]
      expect(body["properties"]["active"]).to eq("type" => "boolean", "example" => true)
    end
  end

  describe "US2: composite literals propagate examples to every leaf" do
    it "carries examples on every property of a literal render json: hash" do
      body = document["paths"]["/api/users"]["post"]["responses"]["201"]["content"]["application/json"]["schema"]
      expect(body["properties"]["id"]).to eq("type" => "integer", "example" => 1)
      expect(body["properties"]["role"]).to eq("type" => "string", "example" => "member")
    end
  end

  describe "US3: sidecar overrides generated examples (feature 020 interaction)" do
    it "the sidecar's example wins when both an inline render and a sidecar are present" do
      # api/sidecars#inline_render does `render json: { status: "ok" }`. Without
      # the sidecar, we'd see `{type: string, example: "ok"}`. The sidecar
      # declares an enum with no example on `status`, so the user gets the
      # sidecar's contract verbatim — confirming sidecar precedence (FR-005).
      body = schema_at("/api/sidecars/inline_render", "get")
      expect(body["properties"]["status"]).to include("enum" => %w[ok pending error])
      # The sidecar did NOT declare `example` on `status` → none appears.
      expect(body["properties"]["status"]).not_to have_key("example")
    end
  end

  it "produces a valid OpenAPI document" do
    expect(document).to be_a_valid_openapi_document
  end
end
