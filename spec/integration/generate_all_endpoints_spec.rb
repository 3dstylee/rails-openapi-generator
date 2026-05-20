# frozen_string_literal: true

require "json"

RSpec.describe "Generate an OpenAPI document for all endpoints", :rails_app do
  let(:output_path) { File.expand_path("../../tmp/spec/all_endpoints.json", __dir__) }

  def configuration(**overrides)
    RailsOpenapiGenerator::Configuration.new.tap do |config|
      config.output_path = output_path
      overrides.each { |key, value| config.public_send("#{key}=", value) }
    end
  end

  after { FileUtils.rm_rf(File.dirname(output_path)) }

  it "produces an operation for every resolvable route" do
    document = RailsOpenapiGenerator::Generator.new(configuration).document

    expect(document["paths"].keys).to contain_exactly(
      "/api/inputs", "/api/inputs/{id}", "/api/inputs/upload",
      "/api/multi_status/destroy/{id}", "/api/multi_status/dup_distinct",
      "/api/multi_status/dup_same", "/api/multi_status/head_and_render",
      "/api/multi_status/show/{id}", "/api/multi_status/update",
      "/api/orphan", "/api/pages/{id}", "/api/pages/{id}/download",
      "/api/posts",
      "/api/redirects/bounce", "/api/redirects/create", "/api/redirects/mixed",
      "/api/redirects/old_path", "/api/redirects/transfer",
      "/api/reports/chained", "/api/reports/cyclic",
      "/api/template_renders/as_html", "/api/template_renders/destroy/{id}",
      "/api/template_renders/missing", "/api/template_renders/update",
      "/api/reports/single", "/api/reports/via_concern",
      "/api/statuses/guarded", "/api/statuses/make", "/api/statuses/mark",
      "/api/statuses/unmark", "/api/users", "/api/users/{id}"
    )
    expect(document["paths"]["/api/users"].keys).to contain_exactly("get", "post")
  end

  it "generates a valid OpenAPI 3.1 document" do
    document = RailsOpenapiGenerator::Generator.new(configuration).document
    expect(document).to be_a_valid_openapi_document
  end

  it "gives every operation a unique, path-based operationId" do
    document = RailsOpenapiGenerator::Generator.new(configuration).document
    ids = document["paths"].values.flat_map { |operations| operations.values.map { |op| op["operationId"] } }

    expect(ids).to eq(ids.uniq)
    expect(document["paths"]["/api/users/{id}"]["get"]["operationId"]).to eq("get_api_users_id")
  end

  it "tags each operation with its controller class name for grouping in viewers" do
    document = RailsOpenapiGenerator::Generator.new(configuration).document

    expect(document["paths"]["/api/users"]["get"]["tags"]).to eq(["Api::UsersController"])
    expect(document["tags"]).to include(
      { "name" => "Api::UsersController" }, { "name" => "Api::PostsController" }
    )
  end

  it "writes the document to the configured path" do
    report = RailsOpenapiGenerator::Generator.new(configuration).generate

    expect(File).to exist(output_path)
    expect(report.output_path).to eq(output_path)
    expect(JSON.parse(File.read(output_path))).to be_a_valid_openapi_document
  end

  it "skips routes with no backing controller action and reports them" do
    report = RailsOpenapiGenerator::Generator.new(configuration).generate

    expect(report.skipped.map { |entry| entry[:route].path }).to include("/legacy")
  end

  it "produces a valid but empty document when no routes match the filter" do
    document = RailsOpenapiGenerator::Generator.new(configuration(route_filter: ->(_route) { false })).document

    expect(document["paths"]).to eq({})
    expect(document).to be_a_valid_openapi_document
  end
end
