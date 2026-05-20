# frozen_string_literal: true

RSpec.describe RailsOpenapiGenerator::ViewLocator do
  let(:views_root) { File.expand_path("../fixtures/dummy/app/views", __dir__) }

  subject(:locator) { described_class.new(views_root: views_root) }

  def route(controller:, action:)
    RailsOpenapiGenerator::Route.new(http_method: "GET", path: "/x", controller: controller, action: action)
  end

  it "resolves an action to its .json.jbuilder view by convention" do
    match = locator.locate_view(route(controller: "api/users", action: "index"))

    expect(match.kind).to eq(:json)
    expect(match.path).to end_with("app/views/api/users/index.json.jbuilder")
  end

  it "resolves an action to its .html.* view by convention" do
    match = locator.locate_view(route(controller: "api/pages", action: "show"))

    expect(match.kind).to eq(:html)
    expect(match.path).to end_with("app/views/api/pages/show.html.erb")
  end

  it "returns nil when no view exists for the action" do
    expect(locator.locate_view(route(controller: "api/posts", action: "index"))).to be_nil
  end

  it "resolves an explicitly rendered template name (controller-relative)" do
    match = locator.locate_view(route(controller: "api/pages", action: "edit"), "show")

    expect(match.kind).to eq(:html)
    expect(match.path).to end_with("app/views/api/pages/show.html.erb")
  end

  it "resolves a slash-qualified explicitly rendered template name" do
    match = locator.locate_view(route(controller: "api/users", action: "edit"), "api/users/index")

    expect(match.kind).to eq(:json)
    expect(match.path).to end_with("app/views/api/users/index.json.jbuilder")
  end

  describe "format_hint: (feature 011)" do
    let(:r) { route(controller: "api/template_renders", action: "as_html") }

    it "returns the .json.jbuilder view when format_hint: :json and one exists" do
      match = locator.locate_view(r, "api/template_renders/show", format_hint: :json)
      expect(match.kind).to eq(:json)
      expect(match.path).to end_with("app/views/api/template_renders/show.json.jbuilder")
    end

    it "returns the .html.* view when format_hint: :html and one exists" do
      match = locator.locate_view(r, "api/template_renders/show", format_hint: :html)
      expect(match.kind).to eq(:html)
      expect(match.path).to end_with("app/views/api/template_renders/show.html.erb")
    end

    it "returns nil when format_hint: :json but only HTML exists" do
      # api/pages/show only has .html.erb (no .json.jbuilder).
      match = locator.locate_view(route(controller: "api/pages", action: "show"),
                                  "api/pages/show", format_hint: :json)
      expect(match).to be_nil
    end

    it "returns nil when format_hint: :html but only JSON exists" do
      # api/users/index only has .json.jbuilder (no .html.erb).
      match = locator.locate_view(route(controller: "api/users", action: "index"),
                                  "api/users/index", format_hint: :html)
      expect(match).to be_nil
    end

    it "tries each format in order when format_hint is an Array" do
      match = locator.locate_view(r, "api/template_renders/show", format_hint: %i[json html])
      expect(match.kind).to eq(:json)
    end

    it "falls back to today's preference when format_hint is nil" do
      match = locator.locate_view(r, "api/template_renders/show")
      expect(match.kind).to eq(:json)
    end
  end
end
