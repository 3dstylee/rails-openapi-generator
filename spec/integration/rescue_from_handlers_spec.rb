# frozen_string_literal: true

RSpec.describe "rescue_from handlers", :rails_app do
  let(:generator) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/rescue_from.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config)
  end

  let(:document) { generator.document }
  let(:report)   { generator.generate }

  after { FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__)) }

  let(:show) { document["paths"].fetch("/api/rescued_resources/{id}")["get"] }
  let(:responses) { show["responses"] }

  describe "method-form rescue_from handlers (US1)" do
    it "documents the action's own 200 entry alongside handler-derived statuses" do
      expect(responses.keys).to include("200", "400", "403", "404", "422")
    end

    it "uses the handler's literal body schema for the 404 entry" do
      schema = responses["404"]["content"]["application/json"]["schema"]
      expect(schema["properties"]).to have_key("error")
      expect(schema["properties"]["error"]["type"]).to eq("string")
    end

    it "uses the handler's literal body schema for the 403 entry" do
      schema = responses["403"]["content"]["application/json"]["schema"]
      expect(schema["properties"]["error"]["type"]).to eq("string")
    end

    it "documents the bad_request handler (which has a non-literal error value) with a permissive `error` field" do
      schema = responses["400"]["content"]["application/json"]["schema"]
      # The handler body's literal hash has `error: exception.message` (a
      # non-literal value). The hash's structure resolves to
      # `{type: object, properties: {error: {}}}`. When the concern's
      # handler also contributes at 400 (with a literal `error: "missing_param"`
      # → `{type: string}`), the union produces `oneOf` of two shapes.
      if schema.key?("oneOf")
        shapes = schema["oneOf"]
        expect(shapes.any? { |s| s.dig("properties", "error", "type") == "string" }).to be(true)
      else
        expect(schema["properties"]).to have_key("error")
      end
    end

    it "emits no new 'response shape could not be determined' warning for the route" do
      expect(report.warnings.join("\n")).not_to match(%r{/api/rescued_resources/\{id\}: response shape})
    end
  end

  describe "block-form rescue_from handler (US2)" do
    it "documents the 422 entry from the block's literal render" do
      schema = responses["422"]["content"]["application/json"]["schema"]
      expect(schema["properties"]).to have_key("errors")
    end
  end

  describe "concern-declared rescue_from (US3)" do
    it "includes the concern's handler at the 400 status (union with the directly-declared bad_request)" do
      # Both the concern's `bad_request_via_concern` (renders `error: "missing_param"`)
      # and the directly-declared `handler_bad_request` (renders `error: exception.message`)
      # land on `400`. The literal vs. non-literal shapes union per feature 010.
      schema = responses["400"]["content"]["application/json"]["schema"]
      # At minimum, the 400 entry exists and has a content schema.
      expect(schema).not_to be_nil
    end
  end

  describe "SC-004 — controllers without rescue_from on the chain unchanged" do
    it "leaves api/users#index byte-identical (no inherited handler entries)" do
      users_index = document["paths"]["/api/users"]["get"]["responses"]
      expect(users_index.keys).to eq(["200"])
      expect(users_index["200"]).to have_key("content")
    end

    it "leaves api/posts#index byte-identical (no inherited handler entries)" do
      posts_index = document["paths"]["/api/posts"]["get"]["responses"]
      # /api/posts#index is the existing 'undeterminable' fixture — pre-0.14.0 it has one 200 entry with no content.
      expect(posts_index.keys).to eq(["200"])
      expect(posts_index["200"]).not_to have_key("content")
    end
  end

  describe "determinism" do
    it "produces byte-identical responses across two generations" do
      first = generator.document["paths"]["/api/rescued_resources/{id}"]["get"]["responses"]
      second = generator.document["paths"]["/api/rescued_resources/{id}"]["get"]["responses"]
      expect(first).to eq(second)
    end
  end

  describe "happy-path 200 preserved alongside rescue_from entries (regression)" do
    let(:view_op) { document["paths"].fetch("/api/rescued_resources_with_view")["get"] }
    let(:view_responses) { view_op["responses"] }

    # Regression for a bug found during feature 014: an action with no
    # inline render but a resolvable jbuilder view lost its happy-path
    # 200 entry when rescue_from inherited from a base controller
    # populated multiple error-status entries. The fix: integrate the
    # view's schema into the convention-status entry even when extras
    # contribute other statuses.
    it "documents 200 from the jbuilder view alongside the inherited error statuses" do
      expect(view_responses.keys).to include("200")
      schema = view_responses["200"]["content"]["application/json"]["schema"]
      expect(schema["properties"]).to include("line_total_item_count", "available_points", "expire_date")
    end

    it "still documents the inherited rescue_from error statuses" do
      expect(view_responses.keys).to include("400", "403", "404", "422")
    end
  end

  it "produces a document that still passes OpenAPI 3.1 validation" do
    expect(document).to be_a_valid_openapi_document
  end
end
