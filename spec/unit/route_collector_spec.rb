# frozen_string_literal: true

# Minimal stand-ins for the Rails route objects RouteCollector reads.
FakeSpec  = Struct.new(:string) { def to_s = string }
FakePath  = Struct.new(:spec)
FakeRoute = Struct.new(:verb, :path, :defaults)

RSpec.describe RailsOpenapiGenerator::RouteCollector do
  def fake_route(verb:, path:, controller: nil, action: nil)
    defaults = {}
    defaults[:controller] = controller if controller
    defaults[:action] = action if action
    FakeRoute.new(verb, FakePath.new(FakeSpec.new(path)), defaults)
  end

  def rails_app(routes)
    instance_double("Rails::Application", routes: instance_double("RouteSet", routes: routes))
  end

  it "discovers a route for each recognized HTTP method" do
    routes = [
      fake_route(verb: "GET", path: "/users(.:format)", controller: "users", action: "index"),
      fake_route(verb: "POST", path: "/users(.:format)", controller: "users", action: "create")
    ]
    collected = described_class.new(rails_app: rails_app(routes)).collect

    expect(collected.map(&:http_method)).to contain_exactly("GET", "POST")
    expect(collected.map(&:path)).to all(eq("/users"))
  end

  it "strips the optional format suffix from paths" do
    routes = [fake_route(verb: "GET", path: "/users/:id(.:format)", controller: "users", action: "show")]
    collected = described_class.new(rails_app: rails_app(routes)).collect

    expect(collected.first.path).to eq("/users/:id")
    expect(collected.first.path_params).to eq(["id"])
  end

  it "flags routes without a controller/action as external" do
    routes = [fake_route(verb: "GET", path: "/legacy(.:format)")]
    collected = described_class.new(rails_app: rails_app(routes)).collect

    expect(collected.first).to be_external
    expect(collected.first).not_to be_resolvable
  end

  it "applies the configured route filter" do
    routes = [
      fake_route(verb: "GET", path: "/api/users(.:format)", controller: "api/users", action: "index"),
      fake_route(verb: "GET", path: "/admin/users(.:format)", controller: "admin/users", action: "index")
    ]
    filter = ->(route) { route.path.start_with?("/api/") }
    collected = described_class.new(rails_app: rails_app(routes), route_filter: filter).collect

    expect(collected.map(&:path)).to eq(["/api/users"])
  end

  it "returns routes in a deterministic order" do
    routes = [
      fake_route(verb: "POST", path: "/users(.:format)", controller: "users", action: "create"),
      fake_route(verb: "GET", path: "/posts(.:format)", controller: "posts", action: "index"),
      fake_route(verb: "GET", path: "/users(.:format)", controller: "users", action: "index")
    ]
    collected = described_class.new(rails_app: rails_app(routes)).collect

    expect(collected.map { |r| [r.path, r.http_method] }).to eq(
      [["/posts", "GET"], ["/users", "GET"], ["/users", "POST"]]
    )
  end
end
