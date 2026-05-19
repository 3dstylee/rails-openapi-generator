# frozen_string_literal: true

RSpec.describe RailsOpenapiGenerator::Configuration do
  subject(:configuration) { described_class.new }

  describe "defaults" do
    it "uses doc/openapi.json as the default output path" do
      expect(configuration.output_path).to eq("doc/openapi.json")
    end

    it "defaults the api version to 1.0.0" do
      expect(configuration.api_version).to eq("1.0.0")
    end

    it "has no route filter by default" do
      expect(configuration.route_filter).to be_nil
    end
  end

  describe "#format" do
    it "infers :json from a .json output path" do
      configuration.output_path = "doc/api.json"
      expect(configuration.format).to eq(:json)
    end

    it "infers :yaml from a .yaml output path" do
      configuration.output_path = "doc/api.yaml"
      expect(configuration.format).to eq(:yaml)
    end

    it "infers :yaml from a .yml output path" do
      configuration.output_path = "doc/api.yml"
      expect(configuration.format).to eq(:yaml)
    end

    it "honors an explicitly set format over the path extension" do
      configuration.output_path = "doc/api.json"
      configuration.format = :yaml
      expect(configuration.format).to eq(:yaml)
    end
  end

  describe "#validate!" do
    it "returns self for a valid configuration" do
      configuration.output_path = "tmp/spec/openapi.json"
      expect(configuration.validate!).to eq(configuration)
    end

    it "raises ConfigurationError for an unsupported format" do
      configuration.format = :xml
      expect { configuration.validate! }.to raise_error(RailsOpenapiGenerator::ConfigurationError, /format/)
    end

    it "raises ConfigurationError for a blank output path" do
      configuration.output_path = "  "
      expect { configuration.validate! }.to raise_error(RailsOpenapiGenerator::ConfigurationError, /output_path/)
    end
  end
end
