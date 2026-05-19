# frozen_string_literal: true

RSpec.describe RailsOpenapiGenerator::WrapperDownloadResolver, :rails_app do
  let(:controller) { Api::ReportsController }

  let(:actions) do
    file = File.expand_path("../fixtures/dummy/app/controllers/api/reports_controller.rb", __dir__)
    RailsOpenapiGenerator::YardParser.new.parse(file)
  end

  def node(action)
    actions[action].method_node
  end

  def resolver(max_depth: 5)
    walker = RailsOpenapiGenerator::ControllerMethodWalker.new(
      method_resolver: RailsOpenapiGenerator::MethodResolver.new, max_depth: max_depth
    )
    described_class.new(walker: walker)
  end

  describe "single-level resolution (US1)" do
    it "detects a download through a single same-controller wrapper" do
      expect(resolver.download?(controller, node("single"))).to be(true)
    end

    it "returns false for a chain of wrappers that never reaches a download" do
      expect(resolver.download?(controller, node("cyclic"))).to be(false)
    end
  end

  describe "recursive resolution (US2)" do
    it "detects a download through a chain of wrappers" do
      expect(resolver.download?(controller, node("chained"))).to be(true)
    end

    it "detects a download through a wrapper defined in a concern" do
      expect(resolver.download?(controller, node("via_concern"))).to be(true)
    end
  end

  describe "bounded and safe resolution (US3)" do
    it "does not loop on cyclic wrapper methods" do
      expect { resolver.download?(controller, node("cyclic")) }.not_to raise_error
      expect(resolver.download?(controller, node("cyclic"))).to be(false)
    end

    it "stops at the configured maximum depth" do
      shallow = resolver(max_depth: 1)
      # `single` is one wrapper deep — still found at depth 1.
      expect(shallow.download?(controller, node("single"))).to be(true)
      # `chained` is two wrappers deep — not reachable at depth 1.
      expect(shallow.download?(controller, node("chained"))).to be(false)
    end

    it "returns false when given a nil action node" do
      expect(resolver.download?(controller, nil)).to be(false)
    end
  end
end
