# frozen_string_literal: true

# Verifies the response-bodies feature is purely additive: the routes,
# parameters, tags, summaries, descriptions, and source references produced by
# feature 001 are unchanged (spec FR-012).
RSpec.describe "Feature 001 output is unchanged by response bodies", :rails_app do
  let(:document) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/regression.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config).document
  end

  let(:index) { document["paths"]["/api/users"]["get"] }

  it "still discovers every route" do
    expect(document["paths"].keys).to include("/api/users", "/api/users/{id}", "/api/posts", "/api/orphan")
  end

  it "still derives request parameters from rails_param" do
    per_page = index["parameters"].find { |param| param["name"] == "per_page" }
    expect(per_page["schema"]).to include("type" => "integer", "minimum" => 1, "maximum" => 100)
  end

  it "still tags operations by controller class name" do
    expect(index["tags"]).to eq(["Api::UsersController"])
  end

  it "still derives summaries and descriptions from YARD comments" do
    expect(index["summary"]).to eq("Search users")
    expect(index["description"]).to include("Returns the users matching the given filters")
  end

  it "still appends the source file and line to the description" do
    expect(index["description"]).to match(%r{Source: `app/controllers/api/users_controller\.rb:\d+`})
  end

  it "still gives every operation a unique path-based operationId" do
    ids = document["paths"].values.flat_map { |operations| operations.values.map { |op| op["operationId"] } }
    expect(ids).to eq(ids.uniq)
  end

  it "leaves JSON endpoints unmarked by the HTML/download feature (FR-013)" do
    expect(index["responses"].values.first["content"].keys).to eq(["application/json"])
    expect(index["tags"]).to eq(["Api::UsersController"])
    expect(index).not_to have_key("x-renders-html")
    expect(index).not_to have_key("x-sends-file")
  end

  it "leaves a genuinely undeterminable endpoint undeterminable after wrapper resolution (FR-010)" do
    # `posts#index` has no view, no render, and no download wrapper.
    operation = document["paths"]["/api/posts"]["get"]
    expect(operation).not_to have_key("x-sends-file")
    expect(operation["responses"].values.first).not_to have_key("content")
  end

  it "leaves response kind, body, and tags unchanged when explicit-status detection is added (FR-010)" do
    # Explicit-status detection changes only status codes — never the response
    # kind, body schema, or tags of an operation.
    body = index.dig("responses", "200", "content", "application/json", "schema")
    expect(body["type"]).to eq("array")
    expect(index["tags"]).to eq(["Api::UsersController"])
  end

  it "leaves rails_param-derived parameters unchanged when implicit-params detection is added (FR-010)" do
    # The typed/constrained per_page parameter from `param!` is preserved as-is.
    per_page = index["parameters"].find { |param| param["name"] == "per_page" }
    expect(per_page["schema"]).to include("type" => "integer", "minimum" => 1, "maximum" => 100)
  end

  it "excludes no endpoint when exclude_source_paths is unset (FR-006)" do
    # The default empty exclude_source_paths leaves every controller documented.
    expect(document["paths"]).to have_key("/api/posts")
  end

  it "leaves JSON endpoint status, body, and tags unchanged when redirect detection is added (FR-010)" do
    # Redirect detection MUST NOT change the documented response of an action
    # that already classifies as JSON / file_download / html_page / head.
    body = index.dig("responses", "200", "content", "application/json", "schema")
    expect(body["type"]).to eq("array")
    expect(index["tags"]).to eq(["Api::UsersController"])
    expect(index).not_to have_key("x-redirects")
  end

  it "leaves a single-render JSON endpoint byte-identical when multi-status detection is added (SC-005)" do
    # api/users#index has exactly one happy render (via jbuilder view) and no
    # error renders or guard helpers. Multi-status detection MUST emit the
    # same single-entry response under '200' with the array schema, and not
    # spuriously add a second entry.
    responses = index["responses"]
    expect(responses.keys).to eq(["200"])
    expect(responses["200"]["content"]["application/json"]["schema"]["type"]).to eq("array")
  end

  it "leaves a redirect endpoint byte-identical when multi-status detection is added (FR-010)" do
    # /api/redirects/create stays a single-entry 302 — multi-status applies
    # only to JSON-shaped operations. Even if before_action contributes JSON
    # entries, the redirect kind wins and no extra entries leak in.
    redirect = document["paths"]["/api/redirects/create"]["post"]["responses"]
    expect(redirect.keys).to eq(["302"])
    expect(redirect["302"]).not_to have_key("content")
  end

  it "leaves a single-render jbuilder endpoint byte-identical under feature 011 (SC-004)" do
    # api/users#index has exactly one happy render via its jbuilder view
    # (no helper renders, no before_action renders). Feature 011's
    # template-site detection must not add a second entry or change the
    # body schema for it.
    responses = index["responses"]
    expect(responses.keys).to eq(["200"])
    body = responses["200"]["content"]["application/json"]["schema"]
    expect(body["type"]).to eq("array")
  end

  it "leaves a single-render HTML-page endpoint byte-identical under feature 011 (SC-004)" do
    # api/pages#show is a pure HTML page (action body has no render; the
    # view is resolved by classification). Feature 011 must keep it as a
    # single-entry :html_page response with text/html content.
    op = document["paths"]["/api/pages/{id}"]["get"]
    expect(op["x-renders-html"]).to be(true)
    content = op["responses"].values.first["content"]
    expect(content.keys).to eq(["text/html"])
  end
end
