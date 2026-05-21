# frozen_string_literal: true

RSpec.describe "Template renders reached through helpers", :rails_app do
  let(:generator) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/template_renders.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config)
  end

  let(:document) { generator.document }
  let(:report)   { generator.generate }

  after { FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__)) }

  def operation(path, http_method = nil)
    operations = document["paths"].fetch(path)
    http_method ? operations[http_method] : operations.values.first
  end

  describe "happy template render in a helper (US1)" do
    let(:responses) { operation("/api/template_renders/update", "put")["responses"] }

    it "documents the helper's template render under 200 (PUT convention)" do
      expect(responses).to have_key("200")
    end

    it "documents the action body's error render under 409" do
      expect(responses).to have_key("409")
    end

    it "uses the resolved jbuilder schema for the 200 body" do
      schema = responses["200"]["content"]["application/json"]["schema"]
      expect(schema["properties"]).to include("id", "status", "assignments")
    end

    it "uses the literal error schema for the 409 body" do
      schema = responses["409"]["content"]["application/json"]["schema"]
      expect(schema["properties"]).to have_key("message")
    end

    it "emits no 'response shape could not be determined' warning" do
      expect(report.warnings.join("\n")).not_to match(%r{/api/template_renders/update:})
    end
  end

  describe "explicit formats: :html in a helper (US2)" do
    let(:op) { operation("/api/template_renders/as_html", "get") }

    it "classifies the operation as an HTML page" do
      expect(op["x-renders-html"]).to be(true)
    end

    it "documents the response with text/html content" do
      content = op["responses"].values.first["content"]
      expect(content).to have_key("text/html")
      expect(content).not_to have_key("application/json")
    end
  end

  describe "missing-view fallback" do
    let(:responses) { operation("/api/template_renders/missing", "get")["responses"] }

    it "documents one entry under the GET convention 200 with no content" do
      expect(responses.keys).to eq(["200"])
      expect(responses["200"]).not_to have_key("content")
    end

    it "emits no 'response shape could not be determined' warning" do
      expect(report.warnings.join("\n")).not_to match(%r{/api/template_renders/missing:})
    end
  end

  describe "before_action template render (US3)" do
    let(:responses) { operation("/api/template_renders/destroy/{id}", "delete")["responses"] }

    it "documents the action's head :no_content under 204" do
      expect(responses).to have_key("204")
    end

    it "documents the before_action's template render under 403" do
      expect(responses).to have_key("403")
    end

    it "uses the resolved jbuilder schema for the 403 body" do
      schema = responses["403"]["content"]["application/json"]["schema"]
      expect(schema["properties"]).to include("error", "reason")
    end

    it "does not add a 403 entry to actions excluded by only: [:destroy]" do
      # `update` is NOT in the `only:` list, so the forbid_unless_admin
      # callback's 403 entry must not appear there.
      update_responses = operation("/api/template_renders/update", "put")["responses"]
      expect(update_responses).not_to have_key("403")
    end
  end

  it "produces a document that still passes OpenAPI 3.1 validation" do
    expect(document).to be_a_valid_openapi_document
  end
end
