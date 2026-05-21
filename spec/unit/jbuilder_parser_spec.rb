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
    # Literal value → typed + carries example (feature 021).
    expect(schema["properties"]["role"]).to eq("type" => "string", "example" => "member")
    expect(schema["properties"]["id"]).to eq({}) # value expression → permissive
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

  describe "json.<key> partial: resolution (feature 016)" do
    let(:partial_body) do
      <<~JBUILDER
        json.id 1
        json.message "hello"
      JBUILDER
    end

    it "resolves the partial and emits an array when given a positional collection arg" do
      template("activity_logs/_activity_log", partial_body)
      path = template("activity_logs/index", <<~JBUILDER)
        json.today_logs @c, partial: "activity_logs/activity_log", as: :activity_log
      JBUILDER
      schema = described_class.new(views_root: tmp_root).parse(path)

      expect(schema["properties"]["today_logs"]).to eq(
        "type" => "array",
        "items" => {
          "type" => "object",
          "properties" => {
            "id" => { "type" => "integer", "example" => 1 },
            "message" => { "type" => "string", "example" => "hello" }
          }
        }
      )
    end

    it "emits the partial's schema directly when there is no positional arg" do
      template("users/_user", <<~JBUILDER)
        json.id 1
        json.name "n"
      JBUILDER
      path = template("users/show", <<~JBUILDER)
        json.user partial: "users/user"
      JBUILDER
      schema = described_class.new(views_root: tmp_root).parse(path)

      expect(schema["properties"]["user"]).to eq(
        "type" => "object",
        "properties" => {
          "id" => { "type" => "integer", "example" => 1 },
          "name" => { "type" => "string", "example" => "n" }
        }
      )
    end

    it "lets the block body win when both partial: and a block are given (FR-004)" do
      template("activity_logs/_activity_log", partial_body)
      path = template("activity_logs/block_wins", <<~JBUILDER)
        json.today_logs @c, partial: "activity_logs/activity_log", as: :activity_log do
          json.from_block "yes"
        end
      JBUILDER
      schema = described_class.new(views_root: tmp_root).parse(path)

      # The block's body wins — the partial schema must NOT appear.
      items = schema["properties"]["today_logs"]["items"]
      expect(items["properties"].keys).to contain_exactly("from_block")
    end

    it "degrades to a permissive {} when the partial name is non-literal" do
      path = template("activity_logs/non_literal", <<~JBUILDER)
        json.today_logs @c, partial: partial_name, as: :activity_log
      JBUILDER
      expect { described_class.new(views_root: tmp_root).parse(path) }.not_to raise_error
      schema = described_class.new(views_root: tmp_root).parse(path)
      expect(schema["properties"]["today_logs"]).to eq({})
    end
  end

  describe "Rails-style relative partial resolution (feature 022)" do
    it "resolves a bare `json.partial! \"name\"` against the caller's directory first" do
      template("nested/_widget", <<~JBUILDER)
        json.id 1
        json.label "widget"
      JBUILDER
      path = template("nested/index", <<~JBUILDER)
        json.partial! "widget"
      JBUILDER
      schema = described_class.new(views_root: tmp_root).parse(path)

      expect(schema["properties"]).to include("id", "label")
      expect(schema["properties"]["id"]).to eq("type" => "integer", "example" => 1)
    end

    it "still resolves a slash-qualified partial against views_root" do
      template("shared/_user", <<~JBUILDER)
        json.id 1
      JBUILDER
      path = template("nested/show", <<~JBUILDER)
        json.partial! "shared/user"
      JBUILDER
      schema = described_class.new(views_root: tmp_root).parse(path)

      expect(schema["properties"]).to have_key("id")
    end
  end

  describe "modifier-if / modifier-unless body extraction (feature 019)" do
    it "includes a json.<key> guarded by modifier-if" do
      path = template("modifier_if", <<~JBUILDER)
        json.message @message
        json.errors @errors if @errors.present?
      JBUILDER
      schema = described_class.new(views_root: tmp_root).parse(path)
      expect(schema["properties"].keys).to contain_exactly("message", "errors")
    end

    it "includes a json.<key> guarded by modifier-unless" do
      path = template("modifier_unless", <<~JBUILDER)
        json.always 1
        json.optional 2 unless skip?
      JBUILDER
      schema = described_class.new(views_root: tmp_root).parse(path)
      expect(schema["properties"].keys).to contain_exactly("always", "optional")
    end
  end

  describe "case/when branch merging (feature 016)" do
    it "merges every when body and the else body into one schema" do
      path = template("case_when_else", <<~JBUILDER)
        case x
        when 1
          json.a 1
        when 2
          json.b 2
        else
          json.c 3
        end
      JBUILDER
      schema = described_class.new(views_root: tmp_root).parse(path)
      expect(schema["properties"].keys).to contain_exactly("a", "b", "c")
    end

    it "merges every when body when no else is present" do
      path = template("case_when_no_else", <<~JBUILDER)
        case x
        when 1
          json.a 1
        when 2
          json.b 2
        end
      JBUILDER
      schema = described_class.new(views_root: tmp_root).parse(path)
      expect(schema["properties"].keys).to contain_exactly("a", "b")
    end

    it "treats a multi-condition when (when 1, 2) as a single body" do
      path = template("case_multi_when", <<~JBUILDER)
        case x
        when 1, 2
          json.x 1
        end
      JBUILDER
      schema = described_class.new(views_root: tmp_root).parse(path)
      expect(schema["properties"].keys).to contain_exactly("x")
    end

    it "walks a case nested inside an if branch" do
      path = template("nested_case_in_if", <<~JBUILDER)
        if cond
          case y
          when 1
            json.inner 1
          end
        end
      JBUILDER
      schema = described_class.new(views_root: tmp_root).parse(path)
      expect(schema["properties"].keys).to contain_exactly("inner")
    end
  end
end
