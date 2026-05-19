# frozen_string_literal: true

RSpec.describe "Happy-path response bodies", :rails_app do
  let(:document) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/response_bodies.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config).document
  end

  def operation(path, method)
    document["paths"][path][method]
  end

  def schema(path, method)
    operation(path, method).dig("responses", operation(path, method)["responses"].keys.first,
                                "content", "application/json", "schema")
  end

  it "generates a valid OpenAPI document with response bodies" do
    expect(document).to be_a_valid_openapi_document
  end

  it "documents a collection endpoint's response body as an array" do
    body = schema("/api/users", "get")
    expect(body["type"]).to eq("array")
    expect(body["items"]["type"]).to eq("object")
    expect(body["items"]["properties"]).to have_key("name")
  end

  it "documents a member endpoint's response body as an object" do
    body = schema("/api/users/{id}", "get")
    expect(body["type"]).to eq("object")
    expect(body["properties"]).to include("id", "name", "email", "role", "profile")
  end

  it "represents nested objects as nested schemas" do
    body = schema("/api/users/{id}", "get")
    expect(body["properties"]["profile"]).to eq("type" => "object", "properties" => { "bio" => {} })
  end

  it "types a literal render json: response precisely" do
    body = schema("/api/users", "post")
    expect(body["properties"]["active"]).to eq("type" => "boolean")
    expect(body["properties"]["id"]).to eq("type" => "integer")
  end

  it "files the success response under the conventional status code" do
    expect(operation("/api/users", "get")["responses"]).to have_key("200")
    expect(operation("/api/users", "post")["responses"]).to have_key("201")
    expect(operation("/api/users/{id}", "delete")["responses"]).to have_key("204")
  end

  it "omits the body for a no-content (204) response" do
    expect(operation("/api/users/{id}", "delete")["responses"]["204"]).not_to have_key("content")
  end
end
