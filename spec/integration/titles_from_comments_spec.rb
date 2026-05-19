# frozen_string_literal: true

RSpec.describe "Operation titles and descriptions from YARD comments", :rails_app do
  let(:document) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/titles.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config).document
  end

  it "uses the first comment line as the operation summary" do
    expect(document["paths"]["/api/users"]["get"]["summary"]).to eq("Search users")
  end

  it "uses the remaining comment lines as the operation description" do
    expect(document["paths"]["/api/users"]["get"]["description"])
      .to include("Returns the users matching the given filters, newest first.")
  end

  it "appends the controller source file and line to the description" do
    description = document["paths"]["/api/users"]["get"]["description"]
    expect(description).to match(%r{Source: `app/controllers/api/users_controller\.rb:\d+`})
  end

  it "uses only the source reference when the comment is a single line" do
    operation = document["paths"]["/api/users/{id}"]["get"]

    expect(operation["summary"]).to eq("Show a user")
    expect(operation["description"]).to match(%r{\A_Source: `app/controllers/api/users_controller\.rb:\d+`_\z})
  end

  it "still produces an operation for an action with no comment" do
    operation = document["paths"]["/api/users"]["post"]

    expect(operation).not_to have_key("summary")
    expect(operation["description"]).to match(%r{Source: `app/controllers/api/users_controller\.rb:\d+`})
    expect(operation["responses"]).to have_key("200")
  end
end
