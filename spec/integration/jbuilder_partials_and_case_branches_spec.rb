# frozen_string_literal: true

RSpec.describe "jbuilder partials & case/when branches (feature 016)", :rails_app do
  let(:document) do
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.expand_path("../../tmp/spec/jbuilder_partials_and_case_branches.json", __dir__)
    RailsOpenapiGenerator::Generator.new(config).document
  end

  def schema_for(path, method)
    op = document["paths"][path][method]
    op.dig("responses", op["responses"].keys.first, "content", "application/json", "schema")
  end

  describe "json.<key> @c, partial: \"name\", as: :name (US1)" do
    let(:body) { schema_for("/api/activity_logs", "get") }

    it "documents every sibling key as an array of the resolved partial" do
      expect(body["type"]).to eq("object")
      expect(body["properties"].keys).to contain_exactly(
        "today_logs", "week_logs", "month_logs", "old_logs"
      )
      body["properties"].each_value do |entry|
        expect(entry["type"]).to eq("array")
        expect(entry["items"]).to eq(
          "type" => "object",
          "properties" => {
            "id" => { "type" => "integer" },
            "message" => { "type" => "string" },
            "created_at" => { "type" => "string" }
          }
        )
      end
    end

    it "produces byte-identical items schemas across every sibling key" do
      items = body["properties"].values.map { |entry| entry["items"] }
      expect(items.uniq.size).to eq(1)
    end
  end

  describe "case/when branch merging (US2)" do
    let(:body) { schema_for("/api/case_branches/show", "get") }

    it "merges every branch's properties into one object schema" do
      expect(body["type"]).to eq("object")
      expect(body["properties"].keys).to include("a", "b", "c")
      expect(body["properties"]["a"]).to eq("type" => "integer")
      expect(body["properties"]["b"]).to eq("type" => "integer")
      expect(body["properties"]["c"]).to eq("type" => "integer")
    end

    it "also includes a modifier-if guarded property (feature 019)" do
      expect(body["properties"]).to have_key("optional")
    end
  end
end
