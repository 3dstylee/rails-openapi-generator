# frozen_string_literal: true

require "json"
require "yaml"
require "fileutils"

RSpec.describe RailsOpenapiGenerator::Writer do
  let(:document) do
    { "openapi" => "3.1.0", "info" => { "title" => "API", "version" => "1.0.0" }, "paths" => {} }
  end

  let(:tmp_dir) { File.expand_path("../../tmp/spec", __dir__) }

  before { FileUtils.rm_rf(tmp_dir) }
  after  { FileUtils.rm_rf(tmp_dir) }

  def configuration_for(path)
    RailsOpenapiGenerator::Configuration.new.tap { |config| config.output_path = path }
  end

  it "writes a JSON document and creates missing directories" do
    path = File.join(tmp_dir, "nested", "openapi.json")
    written = described_class.new(configuration_for(path)).write(document)

    expect(written).to eq(path)
    expect(JSON.parse(File.read(path))).to eq(document)
  end

  it "writes a YAML document when the format is :yaml" do
    path = File.join(tmp_dir, "openapi.yaml")
    described_class.new(configuration_for(path)).write(document)

    expect(YAML.safe_load_file(path)).to eq(document)
  end

  it "serializes JSON deterministically for unchanged input" do
    writer = described_class.new(configuration_for(File.join(tmp_dir, "openapi.json")))
    expect(writer.serialize(document)).to eq(writer.serialize(document))
  end
end
