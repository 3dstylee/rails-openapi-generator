# frozen_string_literal: true

require "ripper"

RSpec.describe RailsOpenapiGenerator::LiteralEvaluator do
  # Returns the Ripper node for the single expression in `source`.
  def node(source)
    Ripper.sexp(source)[1][0]
  end

  def evaluate(source)
    described_class.evaluate(node(source))
  end

  it "evaluates integers and floats" do
    expect(evaluate("42")).to eq(42)
    expect(evaluate("1.5")).to eq(1.5)
  end

  it "evaluates strings and symbols" do
    expect(evaluate('"hello"')).to eq("hello")
    expect(evaluate(":active")).to eq("active")
  end

  it "evaluates true, false, and nil" do
    expect(evaluate("true")).to be(true)
    expect(evaluate("false")).to be(false)
    expect(evaluate("nil")).to be_nil
  end

  it "evaluates ranges" do
    expect(evaluate("1..10")).to eq(1..10)
    expect(evaluate("1...10")).to eq(1...10)
  end

  it "evaluates arrays, including word arrays" do
    expect(evaluate("[1, 2, 3]")).to eq([1, 2, 3])
    expect(evaluate("%w[a b]")).to eq(%w[a b])
  end

  it "evaluates literal hashes with label, symbol, and string keys" do
    expect(evaluate('{ id: 1, "name" => "x" }')).to eq(id: 1, "name" => "x")
    expect(evaluate("{}")).to eq({})
  end

  it "evaluates nested hashes and arrays" do
    expect(evaluate('{ user: { id: 1 }, tags: ["a"] }')).to eq(user: { id: 1 }, tags: ["a"])
  end

  it "returns UNRESOLVED for a non-literal expression" do
    expect(evaluate("some_method_call")).to eq(described_class::UNRESOLVED)
  end

  it "keeps UNRESOLVED for a non-literal value inside a hash" do
    expect(evaluate("{ a: 1, b: dynamic }")).to eq(a: 1, b: described_class::UNRESOLVED)
  end

  describe ".schema_for" do
    it "types literal values precisely" do
      expect(described_class.schema_for("x")).to eq("type" => "string")
      expect(described_class.schema_for(7)).to eq("type" => "integer")
      expect(described_class.schema_for(true)).to eq("type" => "boolean")
    end

    it "uses a permissive {} schema for UNRESOLVED and nil" do
      expect(described_class.schema_for(described_class::UNRESOLVED)).to eq({})
      expect(described_class.schema_for(nil)).to eq({})
    end

    it "uses permissive {} for unresolved leaves nested in a hash" do
      schema = described_class.schema_for(id: 1, name: described_class::UNRESOLVED)
      expect(schema["properties"]).to eq("id" => { "type" => "integer" }, "name" => {})
    end
  end

  describe "constant references (feature 013)" do
    let(:resolver) { RailsOpenapiGenerator::ConstantResolver.new }

    around do |example|
      previous = described_class.resolver
      described_class.resolver = resolver
      example.run
    ensure
      described_class.resolver = previous
    end

    before do
      stub_const("RogEvalSpec::FOO", %w[x y z].freeze)
      stub_const("RogEvalSpec::NESTED::BAR", 1..5)
    end

    it "resolves a bare constant via :var_ref + :@const" do
      expect(evaluate("RogEvalSpec::FOO".split("::").first)).to eq(RailsOpenapiGenerator::LiteralEvaluator::UNRESOLVED)
      # A bare top-level constant that does exist resolves to its value.
      stub_const("RogTopConst", 42)
      expect(evaluate("RogTopConst")).to eq(42)
    end

    it "resolves a qualified constant via :const_path_ref" do
      expect(evaluate("RogEvalSpec::FOO")).to eq(%w[x y z])
    end

    it "resolves a deeply-qualified constant" do
      expect(evaluate("RogEvalSpec::NESTED::BAR")).to eq(1..5)
    end

    it "resolves a top-level :: constant reference" do
      stub_const("RogTopRef", "hello")
      expect(evaluate("::RogTopRef")).to eq("hello")
    end

    it "returns UNRESOLVED for an unknown constant" do
      expect(evaluate("RogEvalSpec::DEFINITELY_NOT_A_CONSTANT"))
        .to eq(RailsOpenapiGenerator::LiteralEvaluator::UNRESOLVED)
    end

    it "leaves local-variable identifiers UNRESOLVED (regression)" do
      # `:var_ref` carrying a `:@ident` is a local; constants are `:@const`.
      expect(evaluate("current_user")).to eq(RailsOpenapiGenerator::LiteralEvaluator::UNRESOLVED)
    end

    it "returns UNRESOLVED for every constant node case when no resolver is set" do
      described_class.resolver = nil
      stub_const("RogNoResolverConst", %w[a b])
      expect(evaluate("RogNoResolverConst"))
        .to eq(RailsOpenapiGenerator::LiteralEvaluator::UNRESOLVED)
    end
  end
end
