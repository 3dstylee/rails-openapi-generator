# frozen_string_literal: true

RSpec.describe "Redirect responses", :rails_app do
  let(:generator) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/redirect_response.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config)
  end

  let(:document) { generator.document }
  let(:report)   { generator.generate }

  after { FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__)) }

  def operation(path, http_method = nil)
    operations = document["paths"].fetch(path)
    http_method ? operations[http_method] : operations.values.first
  end

  describe "bare redirect_to defaults to 302 (US1)" do
    let(:responses) { operation("/api/redirects/create", "post")["responses"] }

    it "documents the response under '302' (not the POST convention 201)" do
      expect(responses.keys).to eq(["302"])
    end

    it "documents the response with no content (a redirect has no body)" do
      expect(responses["302"]).not_to have_key("content")
    end

    it "emits no 'response shape could not be determined' warning for the route" do
      expect(report.warnings.join("\n")).not_to match(%r{/api/redirects/create:})
    end

    it "describes the operation as a redirect" do
      expect(operation("/api/redirects/create", "post")["description"])
        .to include("Redirects to another URL")
    end
  end

  describe "explicit 3xx status (US2)" do
    it "documents redirect_to status: :see_other under '303'" do
      expect(operation("/api/redirects/transfer", "post")["responses"].keys).to eq(["303"])
    end

    it "documents redirect_to status: 301 under '301'" do
      expect(operation("/api/redirects/old_path", "get")["responses"].keys).to eq(["301"])
    end

    it "documents redirect_back_or_to under '302'" do
      expect(operation("/api/redirects/bounce", "post")["responses"].keys).to eq(["302"])
    end

    it "documents every redirect response with no content" do
      %w[/api/redirects/transfer /api/redirects/old_path /api/redirects/bounce].each do |path|
        response = operation(path)["responses"].values.first
        expect(response).not_to have_key("content"), "expected #{path} to have no body"
      end
    end
  end

  describe "JSON-render precedence over redirect (US3)" do
    let(:mixed) { operation("/api/redirects/mixed", "post") }

    it "documents the mixed render+redirect action as JSON, not a redirect" do
      expect(mixed["responses"].keys).to eq(["201"]) # POST + render json: with no explicit status
      expect(mixed["responses"]["201"]).to have_key("content")
      expect(mixed["responses"]["201"]["content"]).to have_key("application/json")
    end
  end

  describe "warning channel (US3)" do
    it "emits no 'response shape could not be determined' warning for any redirect route" do
      warnings = report.warnings.join("\n")
      %w[/api/redirects/create /api/redirects/transfer
         /api/redirects/old_path /api/redirects/bounce /api/redirects/mixed].each do |path|
        expect(warnings).not_to match(/#{Regexp.escape(path)}: response shape could not be determined/)
      end
    end

    it "still emits the warning for a genuinely undeterminable endpoint (no redirect, no render)" do
      expect(report.warnings.join("\n"))
        .to match(%r{/api/posts: response shape could not be determined})
    end
  end

  it "produces a document that still passes OpenAPI 3.1 validation" do
    expect(document).to be_a_valid_openapi_document
  end
end
