# frozen_string_literal: true

require "ripper"

RSpec.describe RailsOpenapiGenerator::RenderExtractor do
  def extract(source)
    action = RailsOpenapiGenerator::ActionSource.new(
      name: "action", docstring: nil, method_node: Ripper.sexp(source), line: 1
    )
    described_class.new.extract(action)
  end

  it "builds a schema from a literal render json: hash" do
    result = extract('render json: { id: 1, name: "x", active: true }')

    expect(result.renders_json).to be(true)
    expect(result.schema["type"]).to eq("object")
    expect(result.schema["properties"]["id"]).to eq("type" => "integer")
    expect(result.schema["properties"]["name"]).to eq("type" => "string")
    expect(result.schema["properties"]["active"]).to eq("type" => "boolean")
  end

  it "skips an error-status render and picks the happy-path render json:" do
    result = extract(<<~RUBY)
      return render status: :bad_request, json: { message: "nope" } unless thing
      render json: { failed_ids: failed }
    RUBY

    expect(result.renders_json).to be(true)
    expect(result.schema["properties"]).to have_key("failed_ids")
    expect(result.schema["properties"]).not_to have_key("message")
  end

  it "uses a permissive schema for a field whose value is not a literal" do
    result = extract("render json: { failed_ids: failed_screenshot_ids }")

    # An unresolved value must be `{}` (any), not mistyped as a string.
    expect(result.schema["properties"]["failed_ids"]).to eq({})
  end

  it "treats a render with an explicit 2xx status as a happy-path render" do
    result = extract("render json: { id: 1 }, status: :created")
    expect(result.schema["properties"]).to have_key("id")
  end

  it "ignores an action whose only render json: is an error render" do
    result = extract('render status: :not_found, json: { message: "x" }')
    expect(result.renders_json).to be(false)
    expect(result.schema).to be_nil
  end

  it "flags a non-literal render json: as renders_json with no schema" do
    result = extract("render json: current_user")

    expect(result.renders_json).to be(true)
    expect(result.schema).to be_nil
  end

  it "reports renders_json false when the action has no render json:" do
    result = extract("head :ok")

    expect(result.renders_json).to be(false)
    expect(result.schema).to be_nil
  end

  it "returns an empty result for a nil action source" do
    result = described_class.new.extract(nil)
    expect(result.renders_json).to be(false)
    expect(result.explicit_status).to be_nil
    expect(result.head?).to be(false)
  end

  describe "explicit status" do
    it "reads an explicit status from head :symbol" do
      expect(extract("head :ok").explicit_status).to eq(200)
      expect(extract("head :created").explicit_status).to eq(201)
      expect(extract("head :no_content").explicit_status).to eq(204)
    end

    it "reads an explicit status from head <integer>" do
      expect(extract("head 202").explicit_status).to eq(202)
    end

    it "reads an explicit status from a render status: option" do
      expect(extract("render json: {}, status: :created").explicit_status).to eq(201)
    end

    it "ignores an error status and keeps the happy one" do
      result = extract("return render json: {}, status: :unprocessable_entity unless ok\nhead :ok")
      expect(result.explicit_status).to eq(200)
    end

    it "is nil when the action sets no explicit status" do
      expect(extract("render json: {}").explicit_status).to be_nil
    end

    it "is nil for an unrecognized status symbol" do
      expect(extract("head :teapot_party").explicit_status).to be_nil
    end

    it "flags a happy head call" do
      expect(extract("head :ok").head?).to be(true)
      expect(extract("render json: {}").head?).to be(false)
    end
  end

  describe "template-render sites (feature 011)" do
    def template_site(source)
      result = extract(source)
      result.render_sites.find(&:template?)
    end

    it "emits a template site for a String positional render" do
      site = template_site('render "api/users/show"')
      expect(site).not_to be_nil
      expect(site.template_name).to eq("api/users/show")
      expect(site.format_hint).to be_nil
      expect(site.head?).to be(false)
    end

    it "emits a template site for a Symbol positional render" do
      site = template_site("render :edit")
      expect(site.template_name).to eq("edit")
    end

    it "emits a template site for render template:" do
      site = template_site('render template: "api/users/show"')
      expect(site.template_name).to eq("api/users/show")
    end

    it "emits a template site for render action:" do
      site = template_site("render action: :show")
      expect(site.template_name).to eq("show")
    end

    it "records a literal :json format hint" do
      site = template_site('render "api/users/show", formats: :json')
      expect(site.format_hint).to eq(:json)
    end

    it "records a literal :html format hint" do
      site = template_site('render "api/users/show", formats: :html')
      expect(site.format_hint).to eq(:html)
    end

    it "records a literal array format hint" do
      site = template_site('render "api/users/show", formats: [:json, :html]')
      expect(site.format_hint).to eq(%i[json html])
    end

    it "ignores a non-literal format hint" do
      site = template_site('render "api/users/show", formats: dynamic_format')
      expect(site.format_hint).to be_nil
    end

    it "uses the explicit status from a template render" do
      site = template_site('render "api/users/show", status: :created')
      expect(site.explicit_status).to eq(201)
    end

    it "does not emit a template site for render json:" do
      sites = extract("render json: { id: 1 }").render_sites
      expect(sites.none?(&:template?)).to be(true)
    end

    it "does not emit a template site for render html:" do
      sites = extract('render html: "<p>hi</p>".html_safe').render_sites
      expect(sites.none?(&:template?)).to be(true)
    end
  end

  describe "respond_to format gates (feature 012)" do
    def gates(source)
      extract(source).render_sites.select(&:content_type)
    end

    it "emits an application/json gate for `format.json`" do
      sites = gates("respond_to do |format|; format.json; end")
      expect(sites.map(&:content_type)).to eq(["application/json"])
      expect(sites.first.format_hint).to eq(:json)
      expect(sites.first.template_name).to eq(RailsOpenapiGenerator::RenderExtractor::SENTINEL_DEFAULT_VIEW)
    end

    it "emits a text/html gate for `format.html`" do
      sites = gates("respond_to do |format|; format.html; end")
      expect(sites.map(&:content_type)).to eq(["text/html"])
      expect(sites.first.format_hint).to eq(:html)
    end

    it "emits both gates for `format.html { ... }; format.json`" do
      source = <<~RUBY
        respond_to do |format|
          format.html { do_something }
          format.json
        end
      RUBY
      sites = gates(source)
      expect(sites.map(&:content_type)).to contain_exactly("application/json", "text/html")
    end

    it "uses an inline render's schema for `format.json { render json: { id: 1 } }`" do
      source = "respond_to do |format|; format.json { render json: { id: 1, ok: true } }; end"
      sites = gates(source)
      expect(sites.size).to eq(1)
      expect(sites.first.content_type).to eq("application/json")
      expect(sites.first.schema["properties"]).to include("id", "ok")
      expect(sites.first.template_name).to be_nil
    end

    it "ignores unmapped format symbols (`format.xml`)" do
      sites = gates("respond_to do |format|; format.xml; end")
      expect(sites).to be_empty
    end

    it "captures the block parameter name (not hard-coded to `format`)" do
      sites = gates("respond_to do |fmt|; fmt.json; fmt.html; end")
      expect(sites.map(&:content_type)).to contain_exactly("application/json", "text/html")
    end

    it "does not detect bare `format.json` outside a respond_to block" do
      sites = gates("format.json")
      expect(sites).to be_empty
    end

    it "honors an inline render's explicit status (`render json: ..., status: :unprocessable_entity`)" do
      source = "respond_to do |format|; format.json { render json: { error: 1 }, status: :unprocessable_entity }; end"
      sites = gates(source)
      expect(sites.first.content_type).to eq("application/json")
      expect(sites.first.explicit_status).to eq(422)
    end
  end

  describe "redirect status" do
    it "is 302 for a bare redirect_to" do
      expect(extract('redirect_to "/x"').redirect_status).to eq(302)
    end

    it "honors an explicit :see_other status" do
      expect(extract('redirect_to "/x", status: :see_other').redirect_status).to eq(303)
    end

    it "honors an explicit :moved_permanently status" do
      expect(extract('redirect_to "/x", status: :moved_permanently').redirect_status).to eq(301)
    end

    it "honors an explicit integer 301 status" do
      expect(extract('redirect_to "/x", status: 301').redirect_status).to eq(301)
    end

    it "detects redirect_back" do
      expect(extract('redirect_back fallback_location: "/x"').redirect_status).to eq(302)
    end

    it "detects redirect_back_or_to" do
      expect(extract('redirect_back_or_to "/x"').redirect_status).to eq(302)
    end

    it "is nil when the status: option resolves to a non-3xx code" do
      expect(extract('redirect_to "/x", status: :unprocessable_entity').redirect_status).to be_nil
    end

    it "falls back to 302 when the status: symbol is unknown" do
      expect(extract('redirect_to "/x", status: :totally_made_up').redirect_status).to eq(302)
    end

    it "picks the last happy redirect when multiple are present" do
      result = extract(<<~RUBY)
        redirect_to "/a"
        redirect_to "/b", status: :see_other
      RUBY
      expect(result.redirect_status).to eq(303)
    end

    it "is nil when the action has no redirect call" do
      expect(extract("render json: { id: 1 }").redirect_status).to be_nil
    end

    it "is nil for an empty action source" do
      expect(described_class.new.extract(nil).redirect_status).to be_nil
    end
  end

  describe "non-JSON signals" do
    it "detects a send_file call" do
      expect(extract('send_file "/tmp/report.pdf"').file_download).to be(true)
    end

    it "detects a send_data call" do
      expect(extract("send_data bytes, filename: \"x.csv\"").file_download).to be(true)
    end

    it "detects a render html: call" do
      expect(extract('render html: "<p>hi</p>".html_safe').html_inline).to be(true)
    end

    it "captures an explicitly rendered template from render :action" do
      expect(extract("render :edit").template).to eq("edit")
    end

    it "captures an explicitly rendered template from render \"path\"" do
      expect(extract('render "photopea/edit"').template).to eq("photopea/edit")
    end

    it "captures an explicitly rendered template from render template:" do
      expect(extract('render template: "photopea/edit"').template).to eq("photopea/edit")
    end

    it "leaves non-JSON signals false/nil for a plain JSON render" do
      result = extract("render json: { id: 1 }")
      expect(result.file_download).to be(false)
      expect(result.html_inline).to be(false)
      expect(result.template).to be_nil
    end
  end
end
