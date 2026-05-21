# frozen_string_literal: true

RSpec.describe RailsOpenapiGenerator::BeforeActionResolver, :rails_app do
  subject(:resolver) do
    described_class.new(method_resolver: RailsOpenapiGenerator::MethodResolver.new)
  end

  describe "BeforeActionCallback#applies_to?" do
    let(:cb) do
      RailsOpenapiGenerator::BeforeActionCallback.new(
        method_name: "f", method_node: nil, only: nil, except: nil
      )
    end

    it "applies to every action when only and except are both nil" do
      expect(cb.applies_to?("update")).to be(true)
      expect(cb.applies_to?("show")).to be(true)
    end

    it "applies only to actions in `only`" do
      cb.only = Set.new(%w[destroy])
      expect(cb.applies_to?("destroy")).to be(true)
      expect(cb.applies_to?("show")).to be(false)
    end

    it "excludes actions in `except`" do
      cb.except = Set.new(%w[show])
      expect(cb.applies_to?("destroy")).to be(true)
      expect(cb.applies_to?("show")).to be(false)
    end
  end

  describe "#resolve on the dummy MultiStatusController" do
    let(:callbacks) { resolver.resolve(Api::MultiStatusController) }

    it "returns one callback for each before_action method whose body can be resolved" do
      names = callbacks.map(&:method_name)
      expect(names).to include("authenticate", "require_admin")
    end

    it "recovers an `only:` literal-array filter from the controller's own source" do
      require_admin = callbacks.find { |c| c.method_name == "require_admin" }
      expect(require_admin.only).to eq(Set.new(%w[destroy]))
      expect(require_admin.except).to be_nil
    end

    it "leaves only/except nil for a concern-inherited callback" do
      authenticate = callbacks.find { |c| c.method_name == "authenticate" }
      expect(authenticate.only).to be_nil
      expect(authenticate.except).to be_nil
    end

    it "returns AST nodes that can be walked for renders" do
      authenticate = callbacks.find { |c| c.method_name == "authenticate" }
      expect(authenticate.method_node).to be_a(Array)
    end
  end

  describe "#resolve resilience" do
    it "returns [] for a nil controller class" do
      expect(resolver.resolve(nil)).to eq([])
    end

    it "returns [] when the class does not respond to _process_action_callbacks" do
      klass = Class.new
      expect(resolver.resolve(klass)).to eq([])
    end
  end
end
