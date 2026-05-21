# frozen_string_literal: true

RSpec.describe "respond_to format blocks", :rails_app do
  let(:generator) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/respond_to.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config)
  end

  let(:document) { generator.document }
  let(:report)   { generator.generate }

  after { FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__)) }

  def operation(path, http_method = "get")
    document["paths"].fetch(path)[http_method]
  end

  describe "both format.html and format.json (US1)" do
    let(:responses) { operation("/api/respond_to/index")["responses"] }
    let(:content)   { responses["200"]["content"] }

    it "documents one 200 entry whose content carries both content types" do
      expect(responses.keys).to eq(["200"])
      expect(content.keys).to contain_exactly("application/json", "text/html")
    end

    it "sorts content types alphabetically (application/json before text/html)" do
      expect(content.keys).to eq(content.keys.sort)
    end

    it "uses the resolved jbuilder schema for application/json" do
      schema = content["application/json"]["schema"]
      expect(schema["properties"]).to include("id", "name", "metadata")
    end

    it "uses the placeholder string schema for text/html" do
      schema = content["text/html"]["schema"]
      expect(schema).to eq("type" => "string")
    end

    it "emits no 'response shape could not be determined' warning" do
      expect(report.warnings.join("\n")).not_to match(%r{/api/respond_to/index:})
    end
  end

  describe "single-format respond_to (US1)" do
    it "documents json_only with only the application/json content type" do
      content = operation("/api/respond_to/json_only")["responses"]["200"]["content"]
      expect(content.keys).to eq(["application/json"])
      expect(content["application/json"]["schema"]["properties"]).to include("kind", "value")
    end

    it "documents html_only as :html_page (text/html only, vendor extension set)" do
      op = operation("/api/respond_to/html_only")
      expect(op["x-renders-html"]).to be(true)
      content = op["responses"]["200"]["content"]
      expect(content.keys).to eq(["text/html"])
    end
  end

  describe "inline render inside a format block (US2)" do
    let(:content) { operation("/api/respond_to/explicit_json")["responses"]["200"]["content"] }

    it "documents both content types under one status" do
      expect(content.keys).to contain_exactly("application/json", "text/html")
    end

    it "uses the inline render's literal schema for application/json (not the default view)" do
      schema = content["application/json"]["schema"]
      expect(schema["properties"]).to include("id", "ok")
      expect(schema["properties"]).not_to have_key("name") # default view's index.json.jbuilder is NOT used
    end
  end

  describe "unmapped format symbol" do
    it "is documented as if the respond_to block were absent (format.xml ignored)" do
      # The action's only signal is `format.xml`, which is unmapped in v1.
      # With no other render and no view at api/respond_to/unmapped.*,
      # the operation falls back to a body-less 200. Feature 015
      # suppresses the warning for this case.
      responses = operation("/api/respond_to/unmapped")["responses"]
      expect(responses["200"]).not_to have_key("content")
      expect(report.warnings.join("\n")).not_to match(%r{/api/respond_to/unmapped:})
    end
  end

  it "produces a document that still passes OpenAPI 3.1 validation" do
    expect(document).to be_a_valid_openapi_document
  end

  it "produces byte-identical content maps across runs (determinism)" do
    second_op = generator.document["paths"]["/api/respond_to/index"]["get"]
    expect(second_op["responses"]).to eq(operation("/api/respond_to/index")["responses"])
  end
end
