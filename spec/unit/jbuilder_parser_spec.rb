# frozen_string_literal: true

require "fileutils"

RSpec.describe RailsOpenapiGenerator::JbuilderParser do
  let(:views_root) { File.expand_path("../fixtures/dummy/app/views", __dir__) }
  let(:tmp_root)   { File.expand_path("../../tmp/spec/views", __dir__) }

  subject(:parser) { described_class.new(views_root: views_root) }

  after { FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__)) }

  # Writes a jbuilder template under tmp_root and returns its path.
  def template(name, body)
    path = File.join(tmp_root, "#{name}.json.jbuilder")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    path
  end

  it "parses extract!, literal values, and nested blocks into an object schema" do
    schema = parser.parse(File.join(views_root, "api/users/_user.json.jbuilder"))

    expect(schema["type"]).to eq("object")
    expect(schema["properties"].keys).to contain_exactly("id", "name", "email", "role", "profile")
    expect(schema["properties"]["role"]).to eq("type" => "string") # literal value → typed
    expect(schema["properties"]["id"]).to eq({})                   # value expression → permissive
    expect(schema["properties"]["profile"]).to eq(
      "type" => "object", "properties" => { "bio" => {} }
    )
  end

  it "treats a json.array! template as an array schema" do
    schema = parser.parse(File.join(views_root, "api/users/index.json.jbuilder"))

    expect(schema["type"]).to eq("array")
    expect(schema["items"]["type"]).to eq("object")
    expect(schema["items"]["properties"]).to have_key("name")
  end

  it "inlines a json.partial! into the current object" do
    schema = parser.parse(File.join(views_root, "api/users/show.json.jbuilder"))

    expect(schema["type"]).to eq("object")
    expect(schema["properties"]).to have_key("email")
  end

  it "includes the properties of every branch of a conditional (union)" do
    path = template("conditional", <<~JBUILDER)
      json.always 1
      if user.admin?
        json.admin_field "x"
      else
        json.member_field "y"
      end
    JBUILDER
    schema = described_class.new(views_root: tmp_root).parse(path)

    expect(schema["properties"].keys).to contain_exactly("always", "admin_field", "member_field")
  end

  it "returns a permissive object for an unparseable or missing template" do
    expect(parser.parse("/no/such/file.json.jbuilder")).to eq("type" => "object", "properties" => {})
  end
end
