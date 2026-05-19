# frozen_string_literal: true

RSpec.describe RailsOpenapiGenerator::ResponseBuilder do
  subject(:builder) { described_class.new }

  def route(method)
    RailsOpenapiGenerator::Route.new(http_method: method, path: "/x", controller: "x", action: "y")
  end

  def make_render_result(schema: nil, renders_json: false, no_content: false)
    RailsOpenapiGenerator::RenderResult.new(
      schema: schema, renders_json: renders_json, no_content: no_content,
      file_download: false, html_inline: false, template: nil
    )
  end

  def classification(kind, render_result: make_render_result, template_name: nil)
    RailsOpenapiGenerator::Classification.new(
      kind: kind, render_result: render_result, template_name: template_name
    )
  end

  let(:view_schema)   { { "type" => "object", "properties" => { "id" => {} } } }
  let(:render_schema) { { "type" => "object", "properties" => { "ok" => { "type" => "boolean" } } } }

  describe "JSON endpoints" do
    it "uses the jbuilder view schema when the action has no render json:" do
      response = builder.build(route("GET"), classification: classification(:json), view_schema: view_schema)
      expect(response.kind).to eq(:json)
      expect(response.body).to eq(view_schema)
    end

    it "prefers a literal render json: schema over the view schema" do
      result = make_render_result(schema: render_schema, renders_json: true)
      response = builder.build(route("GET"), classification: classification(:json, render_result: result),
                                             view_schema: view_schema)
      expect(response.body).to eq(render_schema)
    end

    it "is undeterminable when neither a render nor a view resolves" do
      response = builder.build(route("GET"), classification: classification(:json), view_schema: nil)
      expect(response).to be_undeterminable
    end

    it "is undeterminable for an :undeterminable classification" do
      response = builder.build(route("GET"), classification: classification(:undeterminable), view_schema: nil)
      expect(response).to be_undeterminable
    end
  end

  describe "HTML page endpoints" do
    it "produces an :html_page response carrying the template name" do
      response = builder.build(route("GET"), classification: classification(:html_page, template_name: "pages/show"))
      expect(response.kind).to eq(:html_page)
      expect(response.page_reference).to eq("pages/show")
      expect(response.body).to be_nil
      expect(response).not_to be_undeterminable
    end
  end

  describe "file download endpoints" do
    it "produces a :file_download response with no body" do
      response = builder.build(route("GET"), classification: classification(:file_download))
      expect(response.kind).to eq(:file_download)
      expect(response.body).to be_nil
    end
  end

  describe "status code" do
    it "uses 200 for GET, PUT, and PATCH" do
      %w[GET PUT PATCH].each do |method|
        response = builder.build(route(method), classification: classification(:json), view_schema: view_schema)
        expect(response.status).to eq(200)
      end
    end

    it "uses 201 for POST" do
      response = builder.build(route("POST"), classification: classification(:json), view_schema: view_schema)
      expect(response.status).to eq(201)
    end

    it "uses 204 with no body for DELETE" do
      response = builder.build(route("DELETE"), classification: classification(:json), view_schema: view_schema)
      expect(response.status).to eq(204)
      expect(response.body).to be_nil
    end

    it "uses 204 when the action does head :no_content" do
      result = make_render_result(no_content: true)
      response = builder.build(route("GET"), classification: classification(:json, render_result: result))
      expect(response.status).to eq(204)
    end
  end
end
