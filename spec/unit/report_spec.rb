# frozen_string_literal: true

RSpec.describe RailsOpenapiGenerator::GenerationReport do
  subject(:report) { described_class.new }

  let(:route) do
    RailsOpenapiGenerator::Route.new(http_method: "GET", path: "/legacy", controller: nil, action: nil, external: true)
  end

  it "starts empty" do
    expect(report.processed_count).to eq(0)
    expect(report.skipped).to be_empty
    expect(report.warnings).to be_empty
  end

  it "records skipped routes with a reason" do
    report.skip(route, "no backing controller action")
    expect(report.skipped).to eq([{ route: route, reason: "no backing controller action" }])
  end

  it "records warnings" do
    report.warn("something odd happened")
    expect(report.warnings).to eq(["something odd happened"])
  end

  it "always reports success (warnings are non-fatal)" do
    report.warn("non-fatal issue")
    expect(report.success?).to be(true)
  end

  it "starts the HTML-page and file-download counters at zero" do
    expect(report.html_page_count).to eq(0)
    expect(report.file_download_count).to eq(0)
  end

  describe "#summary" do
    it "includes processed, skipped, and warning detail" do
      report.processed_count = 3
      report.output_path = "doc/openapi.json"
      report.skip(route, "no backing controller action")
      report.warn("non-literal param!")

      summary = report.summary
      expect(summary).to include("doc/openapi.json")
      expect(summary).to match(/Processed:\s+3 endpoints/)
      expect(summary).to include("GET /legacy (no backing controller action)")
      expect(summary).to include("non-literal param!")
    end

    it "reports the HTML-page and file-download counts" do
      report.html_page_count = 5
      report.file_download_count = 2

      summary = report.summary
      expect(summary).to match(/HTML pages:\s+5 endpoints/)
      expect(summary).to match(/File downloads:\s+2 endpoints/)
    end
  end
end
