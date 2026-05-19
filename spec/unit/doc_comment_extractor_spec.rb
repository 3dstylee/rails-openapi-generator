# frozen_string_literal: true

RSpec.describe RailsOpenapiGenerator::DocCommentExtractor do
  subject(:extractor) { described_class.new }

  def action_source(docstring)
    RailsOpenapiGenerator::ActionSource.new(name: "action", docstring: docstring, method_node: nil)
  end

  it "uses the first line as the summary and the rest as the description" do
    comment = extractor.extract(action_source("Search users\nReturns matching users, newest first."))
    expect(comment.summary).to eq("Search users")
    expect(comment.description).to eq("Returns matching users, newest first.")
  end

  it "leaves the description nil for a single-line comment" do
    comment = extractor.extract(action_source("Show a user"))
    expect(comment.summary).to eq("Show a user")
    expect(comment.description).to be_nil
  end

  it "returns empty fields when the action source is nil" do
    comment = extractor.extract(nil)
    expect(comment.summary).to be_nil
    expect(comment.description).to be_nil
  end

  it "returns empty fields when the docstring is blank" do
    comment = extractor.extract(action_source("   "))
    expect(comment.summary).to be_nil
    expect(comment.description).to be_nil
  end
end
