# frozen_string_literal: true

RSpec.describe RailsOpenapiGenerator::ResponseBuilder do
  subject(:builder) { described_class.new }

  def route(method)
    RailsOpenapiGenerator::Route.new(http_method: method, path: "/x", controller: "x", action: "y")
  end

  def make_render_result(schema: nil, renders_json: false, explicit_status: nil, head: false,
                         redirect_status: nil, render_sites: nil)
    sites = render_sites || derive_sites(schema, renders_json, explicit_status, head)
    RailsOpenapiGenerator::RenderResult.new(
      schema: schema, renders_json: renders_json, explicit_status: explicit_status, head: head,
      file_download: false, html_inline: false, template: nil, redirect_status: redirect_status,
      render_sites: sites
    )
  end

  # Reconstructs the {RenderSite}s the {RenderExtractor} would have produced
  # so unit specs that pre-date feature 010 keep working without restating
  # every render site by hand.
  def derive_sites(schema, renders_json, explicit_status, head)
    sites = []
    if renders_json
      sites << RailsOpenapiGenerator::RenderSite.new(
        explicit_status: explicit_status, schema: schema, head: false, source: :action
      )
    end
    if head
      sites << RailsOpenapiGenerator::RenderSite.new(
        explicit_status: explicit_status || 200, schema: nil, head: true, source: :action
      )
    end
    sites
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

    it "is NOT undeterminable for an :undeterminable classification with no signals (feature 015)" do
      # Feature 015 narrows the undeterminable predicate: a classification
      # of :undeterminable with no render sites and no extras now emits a
      # plain body-less response, not an undeterminable one. The warning
      # gate (Response#undeterminable?) is the user-facing effect.
      response = builder.build(route("GET"), classification: classification(:undeterminable), view_schema: nil)
      expect(response).not_to be_undeterminable
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

  describe "multi-content-type entries (feature 012)" do
    def gate_site(content_type, schema: nil, explicit_status: nil)
      RailsOpenapiGenerator::RenderSite.new(
        explicit_status: explicit_status, schema: schema, head: false, source: :action,
        content_type: content_type
      )
    end

    it "builds an entry with content_types when two distinct content types share a status" do
      result = make_render_result(render_sites: [
                                    gate_site("application/json", schema: render_schema),
                                    gate_site("text/html")
                                  ])
      response = builder.build(route("GET"), classification: classification(:undeterminable, render_result: result))

      entry = response.entries.first
      expect(entry.content_types).to be_a(Hash)
      expect(entry.content_types.keys).to contain_exactly("application/json", "text/html")
      expect(entry.content_types["application/json"]).to eq(render_schema)
      expect(entry.content_types["text/html"]).to be_nil
    end

    it "leaves content_types nil when only one content type contributes at the status" do
      result = make_render_result(render_sites: [gate_site("application/json", schema: render_schema)])
      response = builder.build(route("GET"), classification: classification(:undeterminable, render_result: result))

      entry = response.entries.first
      expect(entry.content_types).to be_nil
      expect(entry.body).to eq(render_schema)
    end

    it "groups distinct statuses with their own entries" do
      err_schema = { "type" => "object", "properties" => { "err" => {} } }
      sites = [
        gate_site("application/json", schema: render_schema, explicit_status: 200),
        gate_site("application/json", schema: err_schema, explicit_status: 422),
        gate_site("text/html", explicit_status: 200)
      ]
      result = make_render_result(render_sites: sites)
      response = builder.build(route("GET"), classification: classification(:undeterminable, render_result: result))

      statuses = response.entries.map(&:status)
      expect(statuses).to eq([200, 422])
      happy = response.entries.find { |entry| entry.status == 200 }
      expect(happy.content_types.keys).to contain_exactly("application/json", "text/html")
    end
  end

  describe "redirect responses" do
    it "uses redirect_status as the status and emits no body" do
      result = make_render_result(redirect_status: 302)
      response = builder.build(route("POST"), classification: classification(:redirect, render_result: result))
      expect(response.status).to eq(302)
      expect(response.body).to be_nil
      expect(response.kind).to eq(:redirect)
    end

    it "is not undeterminable" do
      result = make_render_result(redirect_status: 302)
      response = builder.build(route("POST"), classification: classification(:redirect, render_result: result))
      expect(response).not_to be_undeterminable
    end

    it "honors an explicit 3xx status" do
      result = make_render_result(redirect_status: 303)
      response = builder.build(route("POST"), classification: classification(:redirect, render_result: result))
      expect(response.status).to eq(303)
    end

    it "ignores the HTTP-method convention for a redirect" do
      result = make_render_result(redirect_status: 302)
      get = builder.build(route("GET"), classification: classification(:redirect, render_result: result))
      expect(get.status).to eq(302) # not 200
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
