# frozen_string_literal: true

RSpec.describe RailsOpenapiGenerator::SourceLocator, :rails_app do
  subject(:locator) { described_class.new }

  def route(controller:, action:)
    RailsOpenapiGenerator::Route.new(
      http_method: "GET", path: "/x", controller: controller, action: action
    )
  end

  it "resolves a route to its controller source file" do
    file = locator.locate(route(controller: "api/users", action: "index"))

    expect(file).to end_with("app/controllers/api/users_controller.rb")
    expect(File).to exist(file)
  end

  it "returns nil when the controller class does not exist" do
    expect(locator.locate(route(controller: "api/missing", action: "index"))).to be_nil
  end

  it "returns nil for a route with no controller" do
    expect(locator.locate(route(controller: nil, action: nil))).to be_nil
  end
end
