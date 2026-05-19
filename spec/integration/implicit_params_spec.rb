# frozen_string_literal: true

RSpec.describe "Implicit params detection", :rails_app do
  let(:document) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/implicit_params.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config).document
  end

  def operation(path, method)
    document["paths"][path][method]
  end

  def param_names(path, method)
    (operation(path, method)["parameters"] || []).map { |param| param["name"] }
  end

  def body_properties(path, method)
    operation(path, method).dig("requestBody", "content", "application/json", "schema", "properties") || {}
  end

  describe "params[:key] index access (US1)" do
    it "documents a parameter read via params[:key]" do
      # GET /api/inputs/:id reads params[:query].
      expect(param_names("/api/inputs/{id}", "get")).to include("query")
    end

    it "does not duplicate a key that is already a path parameter" do
      names = param_names("/api/inputs/{id}", "get")
      expect(names.count("id")).to eq(1)
    end

    it "does not document Rails-internal keys" do
      expect(param_names("/api/inputs/{id}", "get")).not_to include("format", "controller", "action")
    end

    it "documents implicit parameters with a permissive schema" do
      query_param = operation("/api/inputs/{id}", "get")["parameters"].find { |p| p["name"] == "query" }
      expect(query_param["schema"]).to eq({})
      expect(query_param["required"]).to be(false)
    end
  end

  describe "strong-params calls (US2)" do
    it "documents keys from require / permit / fetch" do
      # POST /api/inputs uses require(:project), permit(:name, :archived), fetch(:token).
      expect(body_properties("/api/inputs", "post").keys).to include("project", "name", "archived", "token")
    end
  end

  describe "params used through a helper method (US3)" do
    it "documents a key read inside a helper the action calls" do
      # POST /api/inputs/upload delegates to store_upload, which reads params[:file].
      expect(body_properties("/api/inputs/upload", "post")).to have_key("file")
    end
  end

  it "produces a document that still passes OpenAPI 3.1 validation" do
    expect(document).to be_a_valid_openapi_document
  end
end
