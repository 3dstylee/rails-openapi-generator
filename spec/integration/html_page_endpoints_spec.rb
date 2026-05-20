# frozen_string_literal: true

RSpec.describe "HTML page & file download endpoints", :rails_app do
  let(:generator) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/html_pages.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config)
  end

  let(:document) { generator.document }
  let(:report)   { generator.generate }

  after { FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__)) }

  def operation(path)
    document["paths"][path].values.first
  end

  describe "an HTML page endpoint (US1)" do
    let(:page) { operation("/api/pages/{id}") }

    it "presents the success response as text/html with no JSON schema" do
      content = page["responses"].values.first["content"]
      expect(content.keys).to eq(["text/html"])
    end

    it "carries a note in the description naming the template" do
      expect(page["description"]).to match(%r{Renders an HTML page \(`api/pages/show`\)})
    end

    it "is grouped under the HTML Pages tag alongside its controller tag" do
      expect(page["tags"]).to eq(["Api::PagesController", "HTML Pages"])
    end

    it "carries the x-renders-html flag and template (US2)" do
      expect(page["x-renders-html"]).to be(true)
      expect(page["x-html-template"]).to eq("api/pages/show")
    end
  end

  describe "a file download endpoint (US1)" do
    let(:download) { operation("/api/pages/{id}/download") }

    it "presents the success response as application/octet-stream" do
      content = download["responses"].values.first["content"]
      expect(content.keys).to eq(["application/octet-stream"])
      expect(content["application/octet-stream"]["schema"]).to eq("type" => "string", "format" => "binary")
    end

    it "carries a download note and the File Downloads tag" do
      expect(download["description"]).to match(/Sends a file download/)
      expect(download["tags"]).to eq(["Api::PagesController", "File Downloads"])
    end

    it "carries the x-sends-file flag (US2)" do
      expect(download["x-sends-file"]).to be(true)
    end
  end

  describe "JSON endpoints are not marked (US1)" do
    let(:json_op) { operation("/api/users") }

    it "keeps an application/json response and no kind tag" do
      expect(json_op["responses"].values.first["content"].keys).to eq(["application/json"])
      expect(json_op["tags"]).to eq(["Api::UsersController"])
    end

    it "carries no x-renders-html / x-sends-file flag" do
      expect(json_op).not_to have_key("x-renders-html")
      expect(json_op).not_to have_key("x-sends-file")
    end
  end

  it "produces a document that still passes OpenAPI 3.1 validation" do
    expect(document).to be_a_valid_openapi_document
  end

  it "reports the HTML-page and file-download counts (US3)" do
    # Three HTML pages in the fixture: `api/pages#show` (existing),
    # `api/template_renders#as_html` (feature 011), and
    # `api/respond_to#html_only` (new in feature 012 — a `respond_to`
    # block with only `format.html` resolves the default `.html.erb`).
    expect(report.html_page_count).to eq(3)
    expect(report.file_download_count).to be >= 1
    expect(report.summary).to match(/HTML pages:\s+3 endpoints/)
  end

  it "adds HTML Pages and File Downloads to the top-level tags" do
    names = document["tags"].map { |tag| tag["name"] }
    expect(names).to include("HTML Pages", "File Downloads")
  end
end
