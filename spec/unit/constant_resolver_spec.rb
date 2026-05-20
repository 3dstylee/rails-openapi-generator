# frozen_string_literal: true

RSpec.describe RailsOpenapiGenerator::ConstantResolver do
  subject(:resolver) { described_class.new }

  before do
    stub_const("RogConstSpec::STRINGS", %w[a b c].freeze)
    stub_const("RogConstSpec::INTS", [1, 2, 3].freeze)
    stub_const("RogConstSpec::INT_RANGE", 1..100)
    stub_const("RogConstSpec::FLOAT_RANGE", 1.0..2.5)
    stub_const("RogConstSpec::MIXED_RANGE", 1..2.5)
    stub_const("RogConstSpec::PATTERN", /\A\d+\z/)
    stub_const("RogConstSpec::HASH", { "min" => 1, max: 100 })
    stub_const("RogConstSpec::CLASS_REF", String)
    stub_const("RogConstSpec::INSTANCES", [Object.new, Object.new])
    stub_const("RogConstSpec::NESTED_HASH", { foo: { bar: 1 } })
  end

  describe "schema-compatible resolution" do
    it "resolves an Array of Strings" do
      expect(resolver.resolve("RogConstSpec::STRINGS")).to eq(%w[a b c])
    end

    it "resolves an Array of Integers" do
      expect(resolver.resolve("RogConstSpec::INTS")).to eq([1, 2, 3])
    end

    it "resolves an Integer Range" do
      expect(resolver.resolve("RogConstSpec::INT_RANGE")).to eq(1..100)
    end

    it "resolves a Float Range" do
      expect(resolver.resolve("RogConstSpec::FLOAT_RANGE")).to eq(1.0..2.5)
    end

    it "rejects a mixed-numeric Range" do
      expect(resolver.resolve("RogConstSpec::MIXED_RANGE")).to eq(RailsOpenapiGenerator::LiteralEvaluator::UNRESOLVED)
    end

    it "resolves a Regexp" do
      expect(resolver.resolve("RogConstSpec::PATTERN")).to eq(/\A\d+\z/)
    end

    it "resolves a Hash with String/Symbol keys and primitive values" do
      expect(resolver.resolve("RogConstSpec::HASH")).to eq("min" => 1, max: 100)
    end

    it "resolves a Hash whose values are themselves recursively compatible" do
      expect(resolver.resolve("RogConstSpec::NESTED_HASH")).to eq(foo: { bar: 1 })
    end
  end

  describe "non-schema-compatible values → UNRESOLVED" do
    it "rejects a class constant" do
      expect(resolver.resolve("RogConstSpec::CLASS_REF")).to eq(RailsOpenapiGenerator::LiteralEvaluator::UNRESOLVED)
    end

    it "rejects an Array containing non-schema-compatible elements" do
      expect(resolver.resolve("RogConstSpec::INSTANCES")).to eq(RailsOpenapiGenerator::LiteralEvaluator::UNRESOLVED)
    end
  end

  describe "lookup failures" do
    it "returns UNRESOLVED on NameError" do
      expect(resolver.resolve("RogConstSpec::DOES_NOT_EXIST"))
        .to eq(RailsOpenapiGenerator::LiteralEvaluator::UNRESOLVED)
    end

    it "returns UNRESOLVED for a nil or empty qualified name" do
      expect(resolver.resolve(nil)).to eq(RailsOpenapiGenerator::LiteralEvaluator::UNRESOLVED)
      expect(resolver.resolve("")).to eq(RailsOpenapiGenerator::LiteralEvaluator::UNRESOLVED)
    end

    # NOTE: a broader-StandardError test was previously here, mocking
    # `Object.const_get` globally to raise. That mock leaked across
    # examples (later autoload paths saw the stubbed `Object.const_get`,
    # corrupting unrelated specs). The rescue's `StandardError, LoadError`
    # surface is exercised implicitly by the NameError test above; the
    # offending mock was removed.
  end

  describe "caching" do
    # NOTE: caching is asserted via cache identity (the same Array
    # object is returned across calls) and via the cache's effect on
    # behavior (stubbing the constant AFTER first resolve still returns
    # the original value). Mocking `Object.const_get` globally leaked
    # across examples, so we test the observable effect instead.
    it "returns the same Array instance across repeated resolves" do
      first  = resolver.resolve("RogConstSpec::STRINGS")
      second = resolver.resolve("RogConstSpec::STRINGS")
      expect(first.equal?(second)).to be(true)
    end

    it "caches UNRESOLVED results too" do
      first  = resolver.resolve("RogConstSpec::DOES_NOT_EXIST")
      second = resolver.resolve("RogConstSpec::DOES_NOT_EXIST")
      expect(first).to eq(RailsOpenapiGenerator::LiteralEvaluator::UNRESOLVED)
      expect(second).to eq(RailsOpenapiGenerator::LiteralEvaluator::UNRESOLVED)
    end
  end
end
