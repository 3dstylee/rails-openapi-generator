# frozen_string_literal: true

RSpec.describe "Constant references in param!", :rails_app do
  let(:generator) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/constant_references.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config)
  end

  let(:document) { generator.document }
  let(:report)   { generator.generate }

  after { FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__)) }

  def operation(path, http_method)
    document["paths"].fetch(path)[http_method]
  end

  let(:moods) { %w[modern classic minimalist scandinavian industrial] }

  describe "top-level param! :in, with a constant Array (US1)" do
    let(:op)   { operation("/api/constant_references/execute", "post") }
    let(:body) { op.dig("requestBody", "content", "application/json", "schema") }

    it "documents the mood property with the constant's enum" do
      mood = body["properties"]["mood"]
      expect(mood["type"]).to eq("string")
      expect(mood["enum"]).to eq(moods)
    end

    it "emits no 'non-literal param! arguments for mood' warning" do
      expect(report.warnings.join("\n"))
        .not_to match(%r{/api/constant_references/execute: non-literal param! arguments for mood})
    end
  end

  describe "Range constant → minimum / maximum (US1)" do
    let(:page) do
      op = operation("/api/constant_references/range", "get")
      op["parameters"].find { |param| param["name"] == "page" }
    end

    it "documents minimum and maximum from the resolved Range" do
      expect(page["schema"]["minimum"]).to eq(1)
      expect(page["schema"]["maximum"]).to eq(100)
    end
  end

  describe "Regexp constant → pattern (US1)" do
    let(:email) do
      op = operation("/api/constant_references/pattern", "get")
      op["parameters"].find { |param| param["name"] == "email" }
    end

    it "documents pattern from the resolved Regexp's source" do
      expect(email["schema"]["pattern"]).to eq('\A[^@\s]+@[^@\s]+\z')
    end
  end

  describe "nested param! block referencing the same constant (US2)" do
    let(:op)   { operation("/api/constant_references/execute", "post") }
    let(:body) { op.dig("requestBody", "content", "application/json", "schema") }

    # Feature 008 (nested `param!` blocks) is now implemented — the
    # inner `p.param! i, String, in: ...::MOODS` is walked and feature
    # 013's constant resolver populates the items.enum. The full user
    # report (`mood` + `moods.items`) is documented end-to-end.
    it "documents the inner items schema with the constant's enum" do
      moods_field = body["properties"]["moods"]
      expect(moods_field["type"]).to eq("array")
      expect(moods_field["items"]["type"]).to eq("string")
      expect(moods_field["items"]["enum"]).to eq(moods)
    end
  end

  describe "non-schema-compatible constant (a class)" do
    let(:op) { operation("/api/constant_references/non_compatible", "get") }

    it "documents the parameter without an enum" do
      x = op["parameters"].find { |param| param["name"] == "x" }
      expect(x["schema"]).not_to have_key("enum")
    end

    it "emits the existing 'non-literal param! arguments' warning" do
      expect(report.warnings.join("\n"))
        .to match(%r{/api/constant_references/non_compatible: non-literal param! arguments for x})
    end
  end

  describe "missing constant (NameError)" do
    let(:op) { operation("/api/constant_references/missing", "get") }

    it "documents the parameter without an enum and does not raise" do
      x = op["parameters"].find { |param| param["name"] == "x" }
      expect(x["schema"]).not_to have_key("enum")
    end

    it "emits the existing 'non-literal param! arguments' warning" do
      expect(report.warnings.join("\n"))
        .to match(%r{/api/constant_references/missing: non-literal param! arguments for x})
    end
  end

  describe "determinism" do
    it "produces the same enum order across runs" do
      run1 = generator.document["paths"]["/api/constant_references/execute"]["post"]
      run2 = generator.document["paths"]["/api/constant_references/execute"]["post"]
      expect(run1).to eq(run2)
    end
  end

  it "produces a document that still passes OpenAPI 3.1 validation" do
    expect(document).to be_a_valid_openapi_document
  end
end
