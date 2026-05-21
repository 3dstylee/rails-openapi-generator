# frozen_string_literal: true

RSpec.describe RailsOpenapiGenerator::DocumentBuilder do
  let(:configuration) do
    RailsOpenapiGenerator::Configuration.new.tap do |config|
      config.title = "Test API"
      config.api_version = "2.0.0"
    end
  end

  def endpoint(http_method:, path:, **attrs)
    RailsOpenapiGenerator::Endpoint.new(
      {
        http_method: http_method, path: path, summary: nil, description: nil,
        parameters: [], request_body: nil, operation_id: "#{http_method.downcase}_op",
        response: RailsOpenapiGenerator::Response.new(status: 200)
      }.merge(attrs)
    )
  end

  it "assembles a document with openapi version and info" do
    document = described_class.new(configuration).build([])

    expect(document["openapi"]).to eq("3.1.0")
    expect(document["info"]).to eq("title" => "Test API", "version" => "2.0.0")
    expect(document["paths"]).to eq({})
  end

  it "groups operations of the same path under one path entry" do
    endpoints = [
      endpoint(http_method: "GET", path: "/users"),
      endpoint(http_method: "POST", path: "/users")
    ]
    document = described_class.new(configuration).build(endpoints)

    expect(document["paths"].keys).to eq(["/users"])
    expect(document["paths"]["/users"].keys).to eq(%w[get post])
  end

  it "converts Rails dynamic segments to OpenAPI path syntax" do
    document = described_class.new(configuration).build([endpoint(http_method: "GET", path: "/users/:id")])

    expect(document["paths"].keys).to eq(["/users/{id}"])
  end

  it "sorts paths deterministically" do
    endpoints = [
      endpoint(http_method: "GET", path: "/posts"),
      endpoint(http_method: "GET", path: "/articles")
    ]
    document = described_class.new(configuration).build(endpoints)

    expect(document["paths"].keys).to eq(["/articles", "/posts"])
  end

  it "includes a default response and operationId on every operation" do
    document = described_class.new(configuration).build([endpoint(http_method: "GET", path: "/users")])
    operation = document["paths"]["/users"]["get"]

    expect(operation["operationId"]).to eq("get_op")
    expect(operation["responses"]).to have_key("200")
  end

  it "tags each operation with its controller and lists the tags at the top level" do
    endpoints = [
      endpoint(http_method: "GET", path: "/users", tag: "users"),
      endpoint(http_method: "GET", path: "/posts", tag: "posts")
    ]
    document = described_class.new(configuration).build(endpoints)

    expect(document["tags"]).to eq([{ "name" => "posts" }, { "name" => "users" }])
    expect(document["paths"]["/users"]["get"]["tags"]).to eq(["users"])
  end

  it "omits the top-level tags array when no endpoint is tagged" do
    document = described_class.new(configuration).build([endpoint(http_method: "GET", path: "/users")])

    expect(document).not_to have_key("tags")
    expect(document["paths"]["/users"]["get"]).not_to have_key("tags")
  end

  describe "multi-content-type entries (feature 012)" do
    let(:multi_entry) do
      RailsOpenapiGenerator::ResponseEntry.new(
        status: 200,
        content_types: {
          "application/json" => { "type" => "object", "properties" => { "id" => { "type" => "integer" } } },
          "text/html" => nil
        }
      )
    end
    let(:response) do
      RailsOpenapiGenerator::Response.new(entries: [multi_entry], kind: :json)
    end
    let(:operation) do
      described_class.new(configuration).build([
                                                 endpoint(http_method: "GET", path: "/things", response: response)
                                               ])["paths"]["/things"]["get"]
    end

    it "emits one OpenAPI response key whose content map carries every content type" do
      content = operation["responses"]["200"]["content"]
      expect(content.keys).to contain_exactly("application/json", "text/html")
    end

    it "sorts content-type keys alphabetically for determinism" do
      content = operation["responses"]["200"]["content"]
      expect(content.keys).to eq(content.keys.sort)
    end

    it "uses the entry's schema for content types that carry one" do
      schema = operation["responses"]["200"]["content"]["application/json"]["schema"]
      expect(schema["properties"]).to have_key("id")
    end

    it "uses the placeholder {type: string} schema for body-less content types (text/html)" do
      schema = operation["responses"]["200"]["content"]["text/html"]["schema"]
      expect(schema).to eq("type" => "string")
    end
  end

  describe "redirect responses" do
    let(:redirect) do
      endpoint(
        http_method: "POST", path: "/things",
        response: RailsOpenapiGenerator::Response.new(status: 302, kind: :redirect)
      )
    end
    let(:operation) { described_class.new(configuration).build([redirect])["paths"]["/things"]["post"] }

    it "emits the response under the redirect status with no content (description only)" do
      expect(operation["responses"].keys).to eq(["302"])
      expect(operation["responses"]["302"]).to eq("description" => "Successful response")
    end

    it "adds no vendor extension for a redirect response" do
      expect(operation).not_to have_key("x-renders-html")
      expect(operation).not_to have_key("x-sends-file")
      expect(operation).not_to have_key("x-redirects")
    end
  end

  it "renders summary, description, parameters, and requestBody when present" do
    parameter = RailsOpenapiGenerator::Parameter.new(
      name: "id", location: :path, required: true, schema: { "type" => "integer" }
    )
    body = { "content" => { "application/json" => { "schema" => { "type" => "object" } } } }
    endpoints = [
      endpoint(
        http_method: "PUT", path: "/users/:id", summary: "Update", description: "Updates a user",
        parameters: [parameter], request_body: body
      )
    ]
    operation = described_class.new(configuration).build(endpoints)["paths"]["/users/{id}"]["put"]

    expect(operation["summary"]).to eq("Update")
    expect(operation["description"]).to eq("Updates a user")
    expect(operation["parameters"].first).to include("name" => "id", "in" => "path", "required" => true)
    expect(operation["requestBody"]).to eq(body)
  end
end
