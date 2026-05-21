# frozen_string_literal: true

require "ripper"

RSpec.describe RailsOpenapiGenerator::ParamExtractor do
  def extract(source)
    action = RailsOpenapiGenerator::ActionSource.new(
      name: "action", docstring: nil, method_node: Ripper.sexp(source)
    )
    described_class.new.extract(action)
  end

  it "returns an empty list when there are no param! calls" do
    expect(extract("def index; render json: []; end")).to eq([])
  end

  it "extracts a parameter name and type" do
    call = extract("param! :query, String").first
    expect(call.name).to eq("query")
    expect(call.type).to eq("String")
    expect(call.required).to be(false)
    expect(call).to be_fully_resolved
  end

  it "reads the required: option" do
    call = extract("param! :id, Integer, required: true").first
    expect(call.required).to be(true)
  end

  it "captures a range constraint" do
    call = extract("param! :per_page, Integer, in: 1..100").first
    expect(call.constraints).to eq(in: 1..100)
  end

  it "captures a word-array constraint" do
    call = extract("param! :role, String, in: %w[admin member]").first
    expect(call.constraints).to eq(in: %w[admin member])
  end

  it "captures a regexp format constraint" do
    call = extract("param! :email, String, format: /.+@.+/").first
    expect(call.constraints[:format]).to eq(".+@.+")
  end

  it "extracts multiple param! calls from one method body" do
    calls = extract("def create; param! :a, String; param! :b, Integer; end")
    expect(calls.map(&:name)).to eq(%w[a b])
  end

  it "flags a non-literal type as not fully resolved" do
    call = extract("param! :thing, dynamic_type").first
    expect(call.type).to be_nil
    expect(call).not_to be_fully_resolved
  end

  it "flags a non-literal option value as not fully resolved" do
    call = extract("param! :thing, Integer, in: computed_range").first
    expect(call).not_to be_fully_resolved
    expect(call.constraints).not_to have_key(:in)
  end

  describe "nested param! blocks (feature 008)" do
    it "extracts Hash nested scalar fields" do
      call = extract(<<~RUBY).first
        param! :q, Hash do |q|
          q.param! :keyword, String
          q.param! :page, Integer
        end
      RUBY
      expect(call.name).to eq("q")
      expect(call.type).to eq("Hash")
      expect(call.nested.map(&:name)).to contain_exactly("keyword", "page")
      expect(call.nested.map(&:type)).to contain_exactly("String", "Integer")
    end

    it "extracts an Array item shape from a nested block" do
      call = extract(<<~RUBY).first
        param! :tags, Array do |a, i|
          a.param! i, String
        end
      RUBY
      expect(call.type).to eq("Array")
      expect(call.nested).to be_a(RailsOpenapiGenerator::ParamCall)
      expect(call.nested.type).to eq("String")
      expect(call.nested.name).to be_nil
    end

    it "carries constraints down to nested ParamCalls" do
      call = extract(<<~RUBY).first
        param! :q, Hash do |q|
          q.param! :page, Integer, in: 1..100
        end
      RUBY
      page = call.nested.first
      expect(page.constraints[:in]).to eq(1..100)
    end

    it "leaves nested nil for an empty block (bare object fallback, FR-007)" do
      call = extract(<<~RUBY).first
        param! :h, Hash do |q|
        end
      RUBY
      expect(call.nested).to eq([])
    end

    it "ignores a block on a non-Hash/Array type (FR-008)" do
      call = extract(<<~RUBY).first
        param! :name, String do |s|
          s.param! :ignored, Integer
        end
      RUBY
      expect(call.nested).to be_nil
    end

    it "does not collect nested param! calls as top-level ParamCalls" do
      calls = extract(<<~RUBY)
        param! :q, Hash do |q|
          q.param! :keyword, String
          q.param! :page, Integer
        end
      RUBY
      expect(calls.map(&:name)).to eq(["q"])
    end

    it "captures the block parameter name (not hard-coded to `q`)" do
      call = extract(<<~RUBY).first
        param! :payload, Hash do |fmt|
          fmt.param! :keyword, String
        end
      RUBY
      expect(call.nested.first.name).to eq("keyword")
    end

    it "rejects nested param! calls on a non-block-var receiver (FR-006)" do
      call = extract(<<~RUBY).first
        param! :q, Hash do |q|
          params.param! :not_nested, String
        end
      RUBY
      expect(call.nested).to eq([])
    end

    it "recurses into a nested Hash within a Hash" do
      call = extract(<<~RUBY).first
        param! :wrapper, Hash do |w|
          w.param! :inner, Hash do |i|
            i.param! :leaf, Integer
          end
        end
      RUBY
      inner = call.nested.first
      expect(inner.name).to eq("inner")
      expect(inner.type).to eq("Hash")
      expect(inner.nested.first.name).to eq("leaf")
    end

    it "stops the descent at the configured depth bound (FR-005)" do
      extractor = described_class.new(max_depth: 1)
      action = RailsOpenapiGenerator::ActionSource.new(
        name: "a", docstring: nil, method_node: Ripper.sexp(<<~RUBY)
          param! :wrapper, Hash do |w|
            w.param! :inner, Hash do |i|
              i.param! :leaf, Integer
            end
          end
        RUBY
      )
      call = extractor.extract(action).first
      inner = call.nested.first
      expect(inner.name).to eq("inner")
      # At depth 1, the inner Hash's block isn't descended.
      expect(inner.nested).to be_nil
    end
  end
end
