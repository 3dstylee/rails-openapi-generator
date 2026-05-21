# frozen_string_literal: true

require "json"

RSpec.describe "Multi-status responses", :rails_app do
  let(:generator) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/multi_status.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config)
  end

  let(:document) { generator.document }
  let(:report)   { generator.generate }

  after { FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__)) }

  def operation(path, http_method = nil)
    operations = document["paths"].fetch(path)
    http_method ? operations[http_method] : operations.values.first
  end

  describe "happy + error renders in the action body (US1)" do
    let(:responses) { operation("/api/multi_status/update", "patch")["responses"] }

    it "documents both the happy (200) and the error (422) renders" do
      expect(responses.keys).to contain_exactly("200", "422", "401")
    end

    it "documents 200 with no content when the entire render value is a non-literal call" do
      # render json: build_payload — fully non-literal → no schema.
      expect(responses["200"]).not_to have_key("content")
    end

    it "documents 422 with the partial schema recovered from the literal hash" do
      # render json: { error_messages: error_messages_for(params) } — the
      # hash structure is literal, even though the value is non-literal,
      # so the schema documents the key name with a permissive value.
      schema = responses["422"]["content"]["application/json"]["schema"]
      expect(schema["properties"]).to have_key("error_messages")
      expect(schema["properties"]["error_messages"]).to eq({})
    end

    it "emits no 'response shape could not be determined' warning for the route" do
      expect(report.warnings.join("\n")).not_to match(%r{/api/multi_status/update:})
    end
  end

  describe "same-status, identical bodies (US1)" do
    let(:responses) { operation("/api/multi_status/dup_same", "post")["responses"] }

    it "collapses two identical-shape renders into one entry under the status" do
      keys = responses.keys.reject { |k| k == "401" }
      expect(keys).to eq(["201"]) # POST convention; no explicit status set
    end

    it "documents the single (deduplicated) literal schema with no oneOf" do
      schema = responses["201"]["content"]["application/json"]["schema"]
      expect(schema).not_to have_key("oneOf")
      expect(schema["properties"].keys).to eq(["ok"])
    end
  end

  describe "same-status, distinct literal bodies (US1)" do
    let(:responses) { operation("/api/multi_status/dup_distinct", "post")["responses"] }

    it "unions the distinct shapes into oneOf under one entry" do
      schema = responses["201"]["content"]["application/json"]["schema"]
      expect(schema).to have_key("oneOf")
      expect(schema["oneOf"].size).to eq(2)
    end

    it "sorts oneOf by canonical JSON ascending for determinism" do
      schema = responses["201"]["content"]["application/json"]["schema"]
      sorted = schema["oneOf"].sort_by { |s| JSON.generate(s) }
      expect(schema["oneOf"]).to eq(sorted)
    end
  end

  describe "head + render at the same status (US1)" do
    let(:responses) { operation("/api/multi_status/head_and_render", "post")["responses"] }

    it "collapses into one entry under 200 with the render's body" do
      expect(responses).to have_key("200")
      schema = responses["200"]["content"]["application/json"]["schema"]
      expect(schema["properties"]).to have_key("id")
      expect(schema).not_to have_key("oneOf")
    end
  end

  describe "before_action callback contributions (US3)" do
    it "adds a 401 entry to every action in the controller (concern-included before_action)" do
      %w[/api/multi_status/update /api/multi_status/dup_same
         /api/multi_status/dup_distinct /api/multi_status/head_and_render].each do |path|
        expect(operation(path)["responses"]).to have_key("401"), "expected #{path} to document 401"
      end
    end

    it "honors only: [:destroy] — 403 appears on destroy but not on show" do
      destroy = operation("/api/multi_status/destroy/{id}", "delete")["responses"]
      show    = operation("/api/multi_status/show/{id}", "get")["responses"]
      expect(destroy).to have_key("403")
      expect(show).not_to have_key("403")
    end

    it "still documents 401 on both destroy and show (concern-wide callback)" do
      destroy = operation("/api/multi_status/destroy/{id}", "delete")["responses"]
      show    = operation("/api/multi_status/show/{id}", "get")["responses"]
      expect(destroy).to have_key("401")
      expect(show).to have_key("401")
    end
  end

  describe "warning channel" do
    # Feature 015: the warning no longer fires for actions with no
    # signals (no render, no view, no extras). The operation is still
    # documented as a body-less 200, but the warning is suppressed.
    it "does NOT emit 'response shape could not be determined' for a no-signal action" do
      expect(report.warnings.join("\n")).not_to match(%r{/api/posts: response shape could not be determined})
    end
  end

  it "produces a document that still passes OpenAPI 3.1 validation" do
    expect(document).to be_a_valid_openapi_document
  end
end
