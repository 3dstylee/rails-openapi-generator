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

  describe "param! description (feature 024)" do
    it "surfaces a query parameter's :description at the parameter level" do
      parameters = document["paths"]["/api/users"]["get"]["parameters"]
      query_param = parameters.find { |param| param["name"] == "query" }

      expect(query_param["description"]).to eq("Free-text search across name and email")
      # The description is lifted out of the schema into the parameter object.
      expect(query_param["schema"]).not_to have_key("description")
    end

    it "leaves the parameter description absent when :description is not given" do
      parameters = document["paths"]["/api/users"]["get"]["parameters"]
      per_page   = parameters.find { |param| param["name"] == "per_page" }

      expect(per_page).not_to have_key("description")
    end

    it "surfaces a body property's :description inside the schema" do
      schema = document["paths"]["/api/users"]["post"]["requestBody"]["content"]["application/json"]["schema"]

      expect(schema["properties"]["name"]).to include("description" => "Display name. 1–100 chars.")
      expect(schema["properties"]["email"]).not_to have_key("description")
    end
  end

  it "still produces an operation for an action with no param! calls" do
    operation = document["paths"]["/api/posts"]["get"]

    expect(operation).not_to have_key("parameters")
    expect(operation["responses"]).to have_key("200")
  end
end
