# frozen_string_literal: true

require "ripper"

RSpec.describe RailsOpenapiGenerator::RenderExtractor do
  def extract(source)
    action = RailsOpenapiGenerator::ActionSource.new(
      name: "action", docstring: nil, method_node: Ripper.sexp(source), line: 1
    )
    described_class.new.extract(action)
  end

  it "builds a schema from a literal render json: hash" do
    result = extract('render json: { id: 1, name: "x", active: true }')

    expect(result.renders_json).to be(true)
    expect(result.schema["type"]).to eq("object")
    expect(result.schema["properties"]["id"]).to eq("type" => "integer")
    expect(result.schema["properties"]["name"]).to eq("type" => "string")
    expect(result.schema["properties"]["active"]).to eq("type" => "boolean")
  end

  it "skips an error-status render and picks the happy-path render json:" do
    result = extract(<<~RUBY)
      return render status: :bad_request, json: { message: "nope" } unless thing
      render json: { failed_ids: failed }
    RUBY

    expect(result.renders_json).to be(true)
    expect(result.schema["properties"]).to have_key("failed_ids")
    expect(result.schema["properties"]).not_to have_key("message")
  end

  it "uses a permissive schema for a field whose value is not a literal" do
    result = extract("render json: { failed_ids: failed_screenshot_ids }")

    # An unresolved value must be `{}` (any), not mistyped as a string.
    expect(result.schema["properties"]["failed_ids"]).to eq({})
  end

  it "treats a render with an explicit 2xx status as a happy-path render" do
    result = extract("render json: { id: 1 }, status: :created")
    expect(result.schema["properties"]).to have_key("id")
  end

  it "ignores an action whose only render json: is an error render" do
    result = extract('render status: :not_found, json: { message: "x" }')
    expect(result.renders_json).to be(false)
    expect(result.schema).to be_nil
  end

  it "flags a non-literal render json: as renders_json with no schema" do
    result = extract("render json: current_user")

    expect(result.renders_json).to be(true)
    expect(result.schema).to be_nil
  end

  it "reports renders_json false when the action has no render json:" do
    result = extract("head :ok")

    expect(result.renders_json).to be(false)
    expect(result.schema).to be_nil
  end

  it "returns an empty result for a nil action source" do
    result = described_class.new.extract(nil)
    expect(result.renders_json).to be(false)
    expect(result.explicit_status).to be_nil
    expect(result.head?).to be(false)
  end

  describe "explicit status" do
    it "reads an explicit status from head :symbol" do
      expect(extract("head :ok").explicit_status).to eq(200)
      expect(extract("head :created").explicit_status).to eq(201)
      expect(extract("head :no_content").explicit_status).to eq(204)
    end

    it "reads an explicit status from head <integer>" do
      expect(extract("head 202").explicit_status).to eq(202)
    end

    it "reads an explicit status from a render status: option" do
      expect(extract("render json: {}, status: :created").explicit_status).to eq(201)
    end

    it "ignores an error status and keeps the happy one" do
      result = extract("return render json: {}, status: :unprocessable_entity unless ok\nhead :ok")
      expect(result.explicit_status).to eq(200)
    end

    it "is nil when the action sets no explicit status" do
      expect(extract("render json: {}").explicit_status).to be_nil
    end

    it "is nil for an unrecognized status symbol" do
      expect(extract("head :teapot_party").explicit_status).to be_nil
    end

    it "flags a happy head call" do
      expect(extract("head :ok").head?).to be(true)
      expect(extract("render json: {}").head?).to be(false)
    end
  end

  describe "redirect status" do
    it "is 302 for a bare redirect_to" do
      expect(extract('redirect_to "/x"').redirect_status).to eq(302)
    end

    it "honors an explicit :see_other status" do
      expect(extract('redirect_to "/x", status: :see_other').redirect_status).to eq(303)
    end

    it "honors an explicit :moved_permanently status" do
      expect(extract('redirect_to "/x", status: :moved_permanently').redirect_status).to eq(301)
    end

    it "honors an explicit integer 301 status" do
      expect(extract('redirect_to "/x", status: 301').redirect_status).to eq(301)
    end

    it "detects redirect_back" do
      expect(extract('redirect_back fallback_location: "/x"').redirect_status).to eq(302)
    end

    it "detects redirect_back_or_to" do
      expect(extract('redirect_back_or_to "/x"').redirect_status).to eq(302)
    end

    it "is nil when the status: option resolves to a non-3xx code" do
      expect(extract('redirect_to "/x", status: :unprocessable_entity').redirect_status).to be_nil
    end

    it "falls back to 302 when the status: symbol is unknown" do
      expect(extract('redirect_to "/x", status: :totally_made_up').redirect_status).to eq(302)
    end

    it "picks the last happy redirect when multiple are present" do
      result = extract(<<~RUBY)
        redirect_to "/a"
        redirect_to "/b", status: :see_other
      RUBY
      expect(result.redirect_status).to eq(303)
    end

    it "is nil when the action has no redirect call" do
      expect(extract("render json: { id: 1 }").redirect_status).to be_nil
    end

    it "is nil for an empty action source" do
      expect(described_class.new.extract(nil).redirect_status).to be_nil
    end
  end

  describe "non-JSON signals" do
    it "detects a send_file call" do
      expect(extract('send_file "/tmp/report.pdf"').file_download).to be(true)
    end

    it "detects a send_data call" do
      expect(extract("send_data bytes, filename: \"x.csv\"").file_download).to be(true)
    end

    it "detects a render html: call" do
      expect(extract('render html: "<p>hi</p>".html_safe').html_inline).to be(true)
    end

    it "captures an explicitly rendered template from render :action" do
      expect(extract("render :edit").template).to eq("edit")
    end

    it "captures an explicitly rendered template from render \"path\"" do
      expect(extract('render "photopea/edit"').template).to eq("photopea/edit")
    end

    it "captures an explicitly rendered template from render template:" do
      expect(extract('render template: "photopea/edit"').template).to eq("photopea/edit")
    end

    it "leaves non-JSON signals false/nil for a plain JSON render" do
      result = extract("render json: { id: 1 }")
      expect(result.file_download).to be(false)
      expect(result.html_inline).to be(false)
      expect(result.template).to be_nil
    end
  end
end
