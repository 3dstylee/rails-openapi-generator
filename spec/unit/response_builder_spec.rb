# frozen_string_literal: true

RSpec.describe RailsOpenapiGenerator::ResponseBuilder do
  subject(:builder) { described_class.new }

  def route(method)
    RailsOpenapiGenerator::Route.new(http_method: method, path: "/x", controller: "x", action: "y")
  end

  def make_render_result(schema: nil, renders_json: false, explicit_status: nil, head: false)
    RailsOpenapiGenerator::RenderResult.new(
      schema: schema, renders_json: renders_json, explicit_status: explicit_status, head: head,
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
    end
  end

  describe "file download endpoints" do
    it "produces a :file_download response with no body" do
      response = builder.build(route("GET"), classification: classification(:file_download))
      expect(response.kind).to eq(:file_download)
      expect(response.body).to be_nil
    end
  end

  describe "status code — HTTP-method convention fallback" do
    it "uses 200 for GET, PUT, and PATCH when no explicit status is set" do
      %w[GET PUT PATCH].each do |method|
        response = builder.build(route(method), classification: classification(:json), view_schema: view_schema)
        expect(response.status).to eq(200)
      end
    end

    it "uses 201 for POST when no explicit status is set" do
      response = builder.build(route("POST"), classification: classification(:json), view_schema: view_schema)
      expect(response.status).to eq(201)
    end

    it "uses 204 with no body for DELETE when no explicit status is set" do
      response = builder.build(route("DELETE"), classification: classification(:json), view_schema: view_schema)
      expect(response.status).to eq(204)
      expect(response.body).to be_nil
    end
  end

  describe "status code — explicit status" do
    it "uses the action's explicit status over the HTTP-method convention" do
      result = make_render_result(explicit_status: 200)
      response = builder.build(route("POST"), classification: classification(:undeterminable, render_result: result))
      expect(response.status).to eq(200) # not 201
    end

    it "documents the same status for actions of different methods that set it explicitly" do
      result = make_render_result(explicit_status: 200, head: true)
      post = builder.build(route("POST"), classification: classification(:undeterminable, render_result: result))
      put  = builder.build(route("PUT"), classification: classification(:undeterminable, render_result: result))
      expect(post.status).to eq(put.status).and(eq(200))
    end

    it "uses an explicit render status: over the HTTP-method convention" do
      result = make_render_result(schema: render_schema, renders_json: true, explicit_status: 201)
      response = builder.build(route("PATCH"), classification: classification(:json, render_result: result))
      expect(response.status).to eq(201)
    end
  end

  describe "head responses (US2)" do
    it "documents no body for a head response" do
      result = make_render_result(explicit_status: 200, head: true)
      response = builder.build(route("GET"), classification: classification(:undeterminable, render_result: result))
      expect(response.body).to be_nil
    end

    it "treats a head response as determinate, not undeterminable" do
      result = make_render_result(explicit_status: 200, head: true)
      response = builder.build(route("GET"), classification: classification(:undeterminable, render_result: result))
      expect(response).not_to be_undeterminable
    end
  end
end
