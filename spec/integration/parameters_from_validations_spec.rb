# frozen_string_literal: true

RSpec.describe "Request parameters from rails_param validations", :rails_app do
  let(:output_path) { File.expand_path("../../tmp/spec/params.json", __dir__) }

  let(:document) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = output_path
    RailsOpenapiGenerator::Generator.new(config).document
  end

  it "derives query parameters with type and required status from param! calls" do
    parameters = document["paths"]["/api/users"]["get"]["parameters"]
    per_page   = parameters.find { |param| param["name"] == "per_page" }

    expect(per_page["in"]).to eq("query")
    expect(per_page["required"]).to be(false)
    expect(per_page["schema"]).to include("type" => "integer")
  end

  it "translates param! constraints into OpenAPI schema constraints" do
    parameters = document["paths"]["/api/users"]["get"]["parameters"]
    per_page   = parameters.find { |param| param["name"] == "per_page" }

    expect(per_page["schema"]).to include("minimum" => 1, "maximum" => 100)
  end

  it "represents dynamic path segments as required path parameters" do
    parameter = document["paths"]["/api/users/{id}"]["get"]["parameters"].first

    expect(parameter).to include("name" => "id", "in" => "path", "required" => true)
    expect(parameter["schema"]).to include("type" => "integer")
  end

  it "builds a request body for write operations from param! calls" do
    schema = document["paths"]["/api/users"]["post"]["requestBody"]["content"]["application/json"]["schema"]

    expect(schema["properties"].keys).to contain_exactly("name", "email", "role")
    expect(schema["required"]).to contain_exactly("name", "email")
  end

  it "still produces an operation for an action with no param! calls" do
    operation = document["paths"]["/api/posts"]["get"]

    expect(operation).not_to have_key("parameters")
    expect(operation["responses"]).to have_key("200")
  end
end
