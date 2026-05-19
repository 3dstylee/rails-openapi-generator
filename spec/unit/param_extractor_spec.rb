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
end
