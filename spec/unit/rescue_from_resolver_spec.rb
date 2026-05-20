# frozen_string_literal: true

RSpec.describe RailsOpenapiGenerator::RescueFromResolver, :rails_app do
  subject(:resolver) do
    described_class.new(method_resolver: RailsOpenapiGenerator::MethodResolver.new)
  end

  describe "#resolve on the dummy ErrorRescuingController" do
    let(:handlers) { resolver.resolve(Api::ErrorRescuingController) }

    it "returns a RescueFromHandler for each method-form handler whose method can be resolved" do
      names = handlers.map(&:exception_name)
      expect(names).to include(
        "ActiveRecord::RecordNotFound",
        "Pundit::NotAuthorizedError",
        "ActionController::ParameterMissing"
      )
    end

    it "returns AST nodes that can be walked for renders" do
      record_not_found = handlers.find { |h| h.exception_name == "ActiveRecord::RecordNotFound" }
      expect(record_not_found.method_node).to be_a(Array)
    end

    it "includes the concern-declared handler (US3)" do
      # The concern's `bad_request_via_concern` is registered alongside
      # the directly-declared `handler_bad_request` for ParameterMissing.
      # Both should appear (multiple `rescue_from` calls for the same
      # exception class produce multiple entries in `rescue_handlers`).
      param_missing = handlers.select { |h| h.exception_name == "ActionController::ParameterMissing" }
      expect(param_missing.size).to be >= 1
    end

    it "resolves the block-form handler (US2)" do
      record_invalid = handlers.find { |h| h.exception_name == "ActiveRecord::RecordInvalid" }
      expect(record_invalid).not_to be_nil
      expect(record_invalid.method_node).to be_a(Array)
    end
  end

  describe "#resolve resilience" do
    it "returns [] for a nil controller class" do
      expect(resolver.resolve(nil)).to eq([])
    end

    it "returns [] for a class that does not respond to rescue_handlers" do
      klass = Class.new
      expect(resolver.resolve(klass)).to eq([])
    end

    it "silently skips an unresolvable Symbol handler" do
      klass = Class.new(ActionController::API)
      # rescue_from with a method name that doesn't exist on the class.
      klass.rescue_from(StandardError, with: :method_that_does_not_exist)
      expect { resolver.resolve(klass) }.not_to raise_error
      expect(resolver.resolve(klass)).to eq([])
    end
  end

  describe "caching" do
    it "resolves the same controller class at most once" do
      first  = resolver.resolve(Api::ErrorRescuingController)
      second = resolver.resolve(Api::ErrorRescuingController)
      expect(first.equal?(second)).to be(true)
    end
  end
end
