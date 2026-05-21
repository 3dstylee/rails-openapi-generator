# frozen_string_literal: true

RSpec.describe RailsOpenapiGenerator::RenderClassifier do
  let(:views_root) { File.expand_path("../fixtures/dummy/app/views", __dir__) }
  let(:view_locator) { RailsOpenapiGenerator::ViewLocator.new(views_root: views_root) }

  subject(:classifier) { described_class.new(view_locator: view_locator) }

  def route(controller:, action:)
    RailsOpenapiGenerator::Route.new(http_method: "GET", path: "/x", controller: controller, action: action)
  end

  def render_result(**overrides)
    RailsOpenapiGenerator::RenderResult.new(
      schema: nil, renders_json: false, explicit_status: nil, head: false,
      file_download: false, html_inline: false, template: nil, redirect_status: nil, **overrides
    )
  end

  it "classifies a JSON render as :json (precedence over everything else)" do
    result = render_result(renders_json: true, file_download: true, html_inline: true)
    classification = classifier.classify(route(controller: "api/users", action: "index"), result)
    expect(classification.kind).to eq(:json)
  end

  it "classifies a send_file action as :file_download" do
    classification = classifier.classify(route(controller: "api/pages", action: "download"),
                                         render_result(file_download: true))
    expect(classification.kind).to eq(:file_download)
  end

  it "classifies a render html: action as :html_page" do
    classification = classifier.classify(route(controller: "api/pages", action: "raw"),
                                         render_result(html_inline: true))
    expect(classification.kind).to eq(:html_page)
  end

  it "classifies an action with a .json.jbuilder view as :json" do
    classification = classifier.classify(route(controller: "api/users", action: "index"), render_result)
    expect(classification.kind).to eq(:json)
    expect(classification.jbuilder_file).to end_with("index.json.jbuilder")
  end

  it "classifies an action with only an .html.* view as :html_page" do
    classification = classifier.classify(route(controller: "api/pages", action: "show"), render_result)
    expect(classification.kind).to eq(:html_page)
    expect(classification.template_name).to eq("api/pages/show")
  end

  it "classifies an action with no render and no view as :undeterminable" do
    classification = classifier.classify(route(controller: "api/posts", action: "index"), render_result)
    expect(classification.kind).to eq(:undeterminable)
  end

  it "classifies an action whose only signal is a redirect as :redirect" do
    classification = classifier.classify(route(controller: "api/posts", action: "index"),
                                         render_result(redirect_status: 302))
    expect(classification.kind).to eq(:redirect)
  end

  it "still classifies as :json when a render json: signal is present alongside a redirect" do
    result = render_result(renders_json: true, redirect_status: 302)
    classification = classifier.classify(route(controller: "api/users", action: "index"), result)
    expect(classification.kind).to eq(:json)
  end

  it "still classifies as :file_download when a download signal is present alongside a redirect" do
    result = render_result(file_download: true, redirect_status: 302)
    classification = classifier.classify(route(controller: "api/pages", action: "download"), result)
    expect(classification.kind).to eq(:file_download)
  end

  it "still classifies as :html_page when an inline-html signal is present alongside a redirect" do
    result = render_result(html_inline: true, redirect_status: 302)
    classification = classifier.classify(route(controller: "api/pages", action: "raw"), result)
    expect(classification.kind).to eq(:html_page)
  end

  it "still classifies as :json via a jbuilder view when a redirect is also present" do
    classification = classifier.classify(route(controller: "api/users", action: "index"),
                                         render_result(redirect_status: 302))
    expect(classification.kind).to eq(:json)
    expect(classification.jbuilder_file).to end_with("index.json.jbuilder")
  end
end
