# frozen_string_literal: true

RSpec.describe RailsOpenapiGenerator::SchemaHoister do
  subject(:hoister) { described_class.new }

  def schema_for(document)
    document["paths"]["/x"]["get"]["responses"]["200"]["content"]["application/json"]["schema"]
  end

  def document_with(schema, path: "/x")
    {
      "openapi" => "3.1.0",
      "paths" => {
        path => {
          "get" => {
            "responses" => {
              "200" => { "content" => { "application/json" => { "schema" => schema } } }
            }
          }
        }
      }
    }
  end

  it "hoists $defs into components/schemas and rewrites the ref" do
    document = document_with({
                               "type" => "object",
                               "properties" => { "items" => { "type" => "array",
                                                              "items" => { "$ref" => "#/$defs/transit_item" } } },
                               "$defs" => { "transit_item" => { "type" => "object",
                                                                "properties" => { "name" => { "type" => "string" } } } }
                             })

    hoister.hoist!(document)

    expect(document["components"]["schemas"]).to eq(
      "transit_item" => { "type" => "object", "properties" => { "name" => { "type" => "string" } } }
    )
    expect(schema_for(document)).not_to have_key("$defs")
    expect(schema_for(document)["properties"]["items"]["items"]["$ref"]).to eq("#/components/schemas/transit_item")
  end

  it "leaves schemas without $defs untouched" do
    document = document_with({ "type" => "object", "properties" => { "id" => { "type" => "integer" } } })

    hoister.hoist!(document)

    expect(document).not_to have_key("components")
    expect(schema_for(document)).to eq("type" => "object", "properties" => { "id" => { "type" => "integer" } })
  end

  it "rewrites refs that appear inside a hoisted definition" do
    document = document_with({
                               "$ref" => "#/$defs/wrapper",
                               "$defs" => {
                                 "wrapper" => { "type" => "object",
                                                "properties" => { "leaf" => { "$ref" => "#/$defs/leaf" } } },
                                 "leaf" => { "type" => "string" }
                               }
                             })

    hoister.hoist!(document)

    expect(document["components"]["schemas"]["wrapper"]["properties"]["leaf"]["$ref"])
      .to eq("#/components/schemas/leaf")
    expect(schema_for(document)["$ref"]).to eq("#/components/schemas/wrapper")
  end

  it "reuses one component key for identical definitions from separate schemas" do
    transit = { "type" => "object", "properties" => { "name" => { "type" => "string" } } }
    document = {
      "openapi" => "3.1.0",
      "paths" => {
        "/a" => { "get" => { "responses" => { "200" => { "content" => { "application/json" => { "schema" =>
          { "$ref" => "#/$defs/transit_item", "$defs" => { "transit_item" => transit } } } } } } } },
        "/b" => { "get" => { "responses" => { "200" => { "content" => { "application/json" => { "schema" =>
          { "$ref" => "#/$defs/transit_item", "$defs" => { "transit_item" => transit } } } } } } } }
      }
    }

    hoister.hoist!(document)

    expect(document["components"]["schemas"].keys).to eq(["transit_item"])
  end

  it "suffixes a clashing definition that differs in shape" do
    document = {
      "openapi" => "3.1.0",
      "paths" => {
        "/a" => { "get" => { "responses" => { "200" => { "content" => { "application/json" => { "schema" =>
          { "$ref" => "#/$defs/item", "$defs" => { "item" => { "type" => "string" } } } } } } } } },
        "/b" => { "get" => { "responses" => { "200" => { "content" => { "application/json" => { "schema" =>
          { "$ref" => "#/$defs/item", "$defs" => { "item" => { "type" => "integer" } } } } } } } } }
      }
    }

    hoister.hoist!(document)

    expect(document["components"]["schemas"].keys).to contain_exactly("item", "item_2")
    refs = %w[/a /b].map do |path|
      document["paths"][path]["get"]["responses"]["200"]["content"]["application/json"]["schema"]["$ref"]
    end
    expect(refs).to contain_exactly("#/components/schemas/item", "#/components/schemas/item_2")
  end
end
