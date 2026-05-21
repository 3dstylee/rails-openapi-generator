# frozen_string_literal: true

require "fileutils"
require "json"

RSpec.describe RailsOpenapiGenerator::SchemaSidecarLoader do
  let(:tmp_root) { File.expand_path("../../tmp/spec/sidecars", __dir__) }
  let(:report)   { instance_double(RailsOpenapiGenerator::GenerationReport, warn: nil) }

  subject(:loader) { described_class.new(report: report) }

  before { FileUtils.mkdir_p(tmp_root) }
  after  { FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__)) }

  def write(name, content)
    path = File.join(tmp_root, name)
    File.write(path, content)
    path
  end

  describe "#for_jbuilder" do
    it "returns the sibling sidecar's parsed contents when present" do
      jbuilder = write("_user.json.jbuilder", "json.id user.id")
      write("_user.schema.json", JSON.generate("type" => "object", "properties" => { "id" => { "type" => "integer" } }))

      expect(loader.for_jbuilder(jbuilder)).to eq(
        "type" => "object", "properties" => { "id" => { "type" => "integer" } }
      )
    end

    it "returns nil when no sibling sidecar exists" do
      jbuilder = write("show.json.jbuilder", "json.id @id")
      expect(loader.for_jbuilder(jbuilder)).to be_nil
    end

    it "returns nil for a path that is not a `.json.jbuilder` template" do
      expect(loader.for_jbuilder("/no/such/path.txt")).to be_nil
    end

    it "warns and returns nil for a malformed sidecar" do
      jbuilder = write("_broken.json.jbuilder", "json.id 1")
      write("_broken.schema.json", "{ broken")

      expect(report).to receive(:warn).with(/_broken\.schema\.json.*failed to parse/)
      expect(loader.for_jbuilder(jbuilder)).to be_nil
    end

    it "caches the parsed sidecar across repeated lookups" do
      jbuilder = write("_cached.json.jbuilder", "json.id 1")
      path = write("_cached.schema.json", JSON.generate("type" => "object"))
      first  = loader.for_jbuilder(jbuilder)
      File.write(path, "{ this would now break }")
      second = loader.for_jbuilder(jbuilder)

      expect(first).to equal(second)
    end
  end

  describe "#for_view" do
    it "returns the sidecar at `<views_root>/<controller>/<action>.schema.json`" do
      FileUtils.mkdir_p(File.join(tmp_root, "api/users"))
      File.write(File.join(tmp_root, "api/users/show.schema.json"),
                 JSON.generate("type" => "object", "properties" => { "id" => { "type" => "integer" } }))

      expect(loader.for_view(tmp_root, "api/users", "show")).to eq(
        "type" => "object", "properties" => { "id" => { "type" => "integer" } }
      )
    end

    it "returns nil when no sidecar exists at the view path" do
      expect(loader.for_view(tmp_root, "api/users", "missing")).to be_nil
    end

    it "returns nil when any of views_root / controller / action is nil" do
      expect(loader.for_view(nil, "api/users", "show")).to be_nil
      expect(loader.for_view(tmp_root, nil, "show")).to be_nil
      expect(loader.for_view(tmp_root, "api/users", nil)).to be_nil
    end
  end
end
