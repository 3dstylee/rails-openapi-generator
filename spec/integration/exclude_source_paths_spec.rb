# frozen_string_literal: true

RSpec.describe "Excluding endpoints by controller source path", :rails_app do
  def generate(exclude_source_paths)
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/exclude.json", __dir__)
    config.exclude_source_paths = exclude_source_paths
    RailsOpenapiGenerator::Generator.new(config)
  end

  describe "exclusion by a source-path substring (US1)" do
    let(:generator) { generate(["posts_controller"]) }

    it "omits endpoints whose controller source file matches the substring" do
      expect(generator.document["paths"]).not_to have_key("/api/posts")
    end

    it "still documents controllers that do not match" do
      expect(generator.document["paths"]).to have_key("/api/users")
    end

    it "records each excluded endpoint as skipped in the run report" do
      report = generator.generate
      reason = report.skipped.find { |entry| entry[:route].path == "/api/posts" }&.dig(:reason)
      expect(reason).to match(/exclude_source_paths/)
    ensure
      FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__))
    end

    it "produces a document that still passes OpenAPI 3.1 validation" do
      expect(generator.document).to be_a_valid_openapi_document
    end
  end

  describe "exclusion by a regexp pattern (US2)" do
    it "omits endpoints whose controller source file matches the regexp" do
      document = generate([%r{api/posts_controller}]).document
      expect(document["paths"]).not_to have_key("/api/posts")
      expect(document["paths"]).to have_key("/api/users")
    end

    it "excludes an endpoint matching either entry of a mixed string/regexp list" do
      document = generate(["posts_controller", %r{api/pages_controller}]).document
      expect(document["paths"]).not_to have_key("/api/posts")
      expect(document["paths"]).not_to have_key("/api/pages/{id}")
    end
  end

  describe "default behavior" do
    it "excludes nothing when exclude_source_paths is empty" do
      expect(generate([]).document["paths"]).to have_key("/api/posts")
    end
  end
end
