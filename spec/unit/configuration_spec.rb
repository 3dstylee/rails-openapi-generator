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

    it "raises ConfigurationError for a non-positive method_resolution_depth" do
      configuration.output_path = "tmp/spec/openapi.json"
      configuration.method_resolution_depth = 0
      expect { configuration.validate! }
        .to raise_error(RailsOpenapiGenerator::ConfigurationError, /method_resolution_depth/)
    end

    it "raises ConfigurationError for a non-integer method_resolution_depth" do
      configuration.output_path = "tmp/spec/openapi.json"
      configuration.method_resolution_depth = "deep"
      expect { configuration.validate! }
        .to raise_error(RailsOpenapiGenerator::ConfigurationError, /method_resolution_depth/)
    end

    it "raises ConfigurationError when exclude_source_paths is not an array" do
      configuration.output_path = "tmp/spec/openapi.json"
      configuration.exclude_source_paths = "vendor/"
      expect { configuration.validate! }
        .to raise_error(RailsOpenapiGenerator::ConfigurationError, /exclude_source_paths/)
    end

    it "raises ConfigurationError when an exclude_source_paths entry is not a string or regexp" do
      configuration.output_path = "tmp/spec/openapi.json"
      configuration.exclude_source_paths = [123]
      expect { configuration.validate! }
        .to raise_error(RailsOpenapiGenerator::ConfigurationError, /exclude_source_paths/)
    end
  end

  describe "#method_resolution_depth" do
    it "defaults to 5" do
      expect(configuration.method_resolution_depth).to eq(5)
    end
  end

  describe "#exclude_source_paths / #source_excluded?" do
    it "defaults to an empty list" do
      expect(configuration.exclude_source_paths).to eq([])
    end

    it "excludes nothing by default" do
      expect(configuration.source_excluded?("/app/controllers/api/users_controller.rb")).to be(false)
    end

    it "matches a String entry as a substring of the path" do
      configuration.exclude_source_paths = ["vendor/"]
      expect(configuration.source_excluded?("/gems/vendor/widgets_controller.rb")).to be(true)
      expect(configuration.source_excluded?("/app/controllers/users_controller.rb")).to be(false)
    end

    it "matches a Regexp entry against the path" do
      configuration.exclude_source_paths = [%r{controllers/legacy/}]
      expect(configuration.source_excluded?("/app/controllers/legacy/old_controller.rb")).to be(true)
      expect(configuration.source_excluded?("/app/controllers/users_controller.rb")).to be(false)
    end

    it "returns false for a nil path" do
      configuration.exclude_source_paths = ["vendor/"]
      expect(configuration.source_excluded?(nil)).to be(false)
    end
  end
end
