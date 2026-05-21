# frozen_string_literal: true

RSpec.describe "Nested param! blocks", :rails_app do
  let(:generator) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/nested_params.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config)
  end

  let(:document) { generator.document }
  let(:report)   { generator.generate }

  after { FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__)) }

  def request_body(path)
    document["paths"].fetch(path)["post"].dig("requestBody", "content", "application/json", "schema")
  end

  describe "Hash with nested scalar fields (US1)" do
    let(:q) { request_body("/api/nested_params/search")["properties"]["q"] }

    it "documents the parameter as an object with nested properties" do
      expect(q["type"]).to eq("object")
      expect(q["properties"].keys).to contain_exactly("keyword", "page")
    end

    it "carries types to nested properties" do
      expect(q["properties"]["keyword"]["type"]).to eq("string")
      expect(q["properties"]["page"]["type"]).to eq("integer")
    end

    it "carries constraints to nested properties" do
      expect(q["properties"]["page"]).to include("minimum" => 1, "maximum" => 100)
    end

    it "sorts nested properties alphabetically" do
      expect(q["properties"].keys).to eq(q["properties"].keys.sort)
    end
  end

  describe "Array with nested item shape (US2)" do
    let(:tags) { request_body("/api/nested_params/tags")["properties"]["tags"] }

    it "documents the parameter as an array with item schema" do
      expect(tags["type"]).to eq("array")
      expect(tags["items"]["type"]).to eq("string")
    end
  end

  describe "Array of String items with constant `in:` (the user's reported case)" do
    let(:moods) { request_body("/api/nested_params/moods")["properties"]["moods"] }
    let(:resolved_moods) { %w[modern classic minimalist scandinavian industrial] }

    it "documents items.type as string" do
      expect(moods["items"]["type"]).to eq("string")
    end

    it "documents items.enum from the resolved constant (feature 013 carry-through)" do
      expect(moods["items"]["enum"]).to eq(resolved_moods)
    end
  end

  describe "Deep nesting (US3)" do
    let(:wrapper) { request_body("/api/nested_params/nested")["properties"]["wrapper"] }

    it "describes all three levels" do
      inner = wrapper.dig("properties", "inner")
      expect(inner["type"]).to eq("object")
      expect(inner.dig("properties", "leaf", "type")).to eq("integer")
    end
  end

  describe "Empty block (FR-007)" do
    let(:h) { request_body("/api/nested_params/empty_block")["properties"]["h"] }

    it "falls back to a bare object schema" do
      expect(h["type"]).to eq("object")
      expect(h["properties"]).to eq({}).or(be_nil)
    end
  end

  describe "Block on non-Hash/Array type (FR-008)" do
    let(:name) { request_body("/api/nested_params/non_hash_block")["properties"]["name"] }

    it "ignores the block and emits a flat schema" do
      expect(name["type"]).to eq("string")
      expect(name).not_to have_key("properties")
    end
  end

  it "produces a document that still passes OpenAPI 3.1 validation" do
    expect(document).to be_a_valid_openapi_document
  end
end
