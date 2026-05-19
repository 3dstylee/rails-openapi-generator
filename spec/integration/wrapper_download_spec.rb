# frozen_string_literal: true

RSpec.describe "File downloads detected through wrapper methods", :rails_app do
  let(:generator) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/wrapper_download.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config)
  end

  let(:document) { generator.document }
  let(:report)   { generator.generate }

  after { FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__)) }

  def operation(path)
    document["paths"][path].values.first
  end

  describe "a download through a single wrapper (US1)" do
    let(:op) { operation("/api/reports/single") }

    it "is classified as a file-download endpoint" do
      content = op["responses"].values.first["content"]
      expect(content.keys).to eq(["application/octet-stream"])
      expect(op["tags"]).to include("File Downloads")
      expect(op["x-sends-file"]).to be(true)
    end
  end

  describe "a download through a chain of wrappers (US2)" do
    it "is classified as a file-download endpoint" do
      op = operation("/api/reports/chained")
      expect(op["x-sends-file"]).to be(true)
    end
  end

  describe "a download through a concern wrapper (US2)" do
    it "is classified as a file-download endpoint" do
      op = operation("/api/reports/via_concern")
      expect(op["x-sends-file"]).to be(true)
    end
  end

  describe "a cyclic wrapper that never downloads (US3)" do
    let(:op) { operation("/api/reports/cyclic") }

    it "is not classified as a file download" do
      expect(op).not_to have_key("x-sends-file")
      expect(op["responses"].values.first).not_to have_key("content")
    end

    it "completes the run without hanging or erroring" do
      expect(report.success?).to be(true)
    end
  end

  it "produces a document that still passes OpenAPI 3.1 validation" do
    expect(document).to be_a_valid_openapi_document
  end

  it "counts wrapper-resolved downloads in the file-download total" do
    expect(report.file_download_count).to be >= 3
  end
end
