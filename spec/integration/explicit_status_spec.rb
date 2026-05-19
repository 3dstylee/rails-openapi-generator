# frozen_string_literal: true

RSpec.describe "Explicit success status codes", :rails_app do
  let(:document) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/explicit_status.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config).document
  end

  def operation(path)
    document["paths"][path].values.first
  end

  describe "explicit status detection (US1)" do
    it "documents a head :ok POST under 200, not the POST convention 201" do
      expect(operation("/api/statuses/mark")["responses"].keys).to eq(["200"])
    end

    it "documents a head :ok PUT under 200" do
      expect(operation("/api/statuses/unmark")["responses"].keys).to eq(["200"])
    end

    it "documents the same status for the head :ok POST and PUT (SC-002)" do
      post = operation("/api/statuses/mark")["responses"].keys
      put  = operation("/api/statuses/unmark")["responses"].keys
      expect(post).to eq(put)
    end

    it "reads the status from a render status: option" do
      expect(operation("/api/statuses/make")["responses"].keys).to eq(["201"])
    end

    it "ignores an error-status guard and uses the happy head status" do
      expect(operation("/api/statuses/guarded")["responses"].keys).to eq(["200"])
    end
  end

  describe "head responses have no body (US2)" do
    it "documents a head response with no content" do
      response = operation("/api/statuses/mark")["responses"]["200"]
      expect(response).not_to have_key("content")
    end

    it "documents head :no_content as 204 with no body" do
      delete = document["paths"]["/api/users/{id}"]["delete"]["responses"]
      expect(delete.keys).to eq(["204"])
      expect(delete["204"]).not_to have_key("content")
    end
  end

  describe "HTTP-method convention fallback (US3)" do
    it "keeps the convention for an action with no explicit status" do
      # POST /api/users (create) sets no explicit status -> POST convention 201.
      expect(document["paths"]["/api/users"]["post"]["responses"].keys).to eq(["201"])
    end

    it "keeps the convention for a GET action with no explicit status" do
      expect(document["paths"]["/api/users"]["get"]["responses"].keys).to eq(["200"])
    end
  end

  it "generates a document that still passes OpenAPI 3.1 validation" do
    expect(document).to be_a_valid_openapi_document
  end
end
