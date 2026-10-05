# frozen_string_literal: true

RSpec.describe "Request parameters declared in helper methods", :rails_app do
  let(:document) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/helper_params.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config).document
  end

  def operation(path, method)
    document["paths"].fetch(path).fetch(method)
  end

  def body_properties(path)
    operation(path, "put").dig("requestBody", "content", "application/json", "schema", "properties")
  end

  def parameters_named(path, method, name)
    operation(path, method)["parameters"].select { |param| param["name"] == name }
  end

  it "builds the request body from param! calls in a helper the action calls" do
    properties = body_properties("/api/helper_params/update/{id}")

    expect(properties.keys).to contain_exactly("title")
    expect(properties["title"]).to include("type" => "string", "description" => "Title of the record")
  end

  it "types the path param from a param! call in the helper" do
    id = parameters_named("/api/helper_params/update/{id}", "put", "id").first

    expect(id["schema"]).to include("type" => "integer")
  end

  it "follows a chain of helpers" do
    id = parameters_named("/api/helper_params/chained/{id}", "put", "id").first

    expect(body_properties("/api/helper_params/chained/{id}").keys).to contain_exactly("title")
    expect(id["schema"]).to include("type" => "integer")
  end

  it "keeps only the action's declaration when the action and a helper declare the same name" do
    query = parameters_named("/api/helper_params/search", "get", "query")

    expect(query.size).to eq(1)
    expect(query.first["description"]).to eq("Declared in the action")
  end
end
