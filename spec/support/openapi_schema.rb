# frozen_string_literal: true

require "json_schemer"

# Validates generated documents against a focused JSON Schema describing the
# OpenAPI 3.1 structures this gem emits (FR-005).
module OpenapiSchema
  SCHEMA = {
    "$schema" => "https://json-schema.org/draft/2020-12/schema",
    "type" => "object",
    "required" => %w[openapi info paths],
    "properties" => {
      "openapi" => { "type" => "string", "pattern" => "^3\\.1\\.\\d+$" },
      "info" => {
        "type" => "object",
        "required" => %w[title version],
        "properties" => {
          "title" => { "type" => "string" },
          "version" => { "type" => "string" }
        }
      },
      "tags" => {
        "type" => "array",
        "items" => {
          "type" => "object",
          "required" => %w[name],
          "properties" => { "name" => { "type" => "string" } }
        }
      },
      "paths" => {
        "type" => "object",
        "additionalProperties" => {
          "type" => "object",
          "additionalProperties" => {
            "type" => "object",
            "required" => %w[responses],
            "properties" => {
              "operationId" => { "type" => "string" },
              "tags" => { "type" => "array", "items" => { "type" => "string" } },
              "summary" => { "type" => "string" },
              "description" => { "type" => "string" },
              "parameters" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "required" => %w[name in],
                  "properties" => {
                    "name" => { "type" => "string" },
                    "in" => { "enum" => %w[path query header cookie] },
                    "required" => { "type" => "boolean" },
                    "schema" => { "type" => "object" }
                  }
                }
              },
              "requestBody" => { "type" => "object" },
              "responses" => {
                "type" => "object",
                "minProperties" => 1,
                "additionalProperties" => {
                  "type" => "object",
                  "required" => %w[description],
                  "properties" => {
                    "description" => { "type" => "string" },
                    "content" => {
                      "type" => "object",
                      "additionalProperties" => {
                        "type" => "object",
                        "properties" => { "schema" => { "type" => "object" } }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }.freeze

  def self.errors(document)
    JSONSchemer.schema(SCHEMA).validate(document).map { |error| error["error"] }
  end

  def self.valid?(document)
    errors(document).empty?
  end
end

RSpec::Matchers.define :be_a_valid_openapi_document do
  match { |document| OpenapiSchema.valid?(document) }

  failure_message do |document|
    "expected a valid OpenAPI 3.1 document, but got errors:\n  #{OpenapiSchema.errors(document).join("\n  ")}"
  end
end
