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
end
