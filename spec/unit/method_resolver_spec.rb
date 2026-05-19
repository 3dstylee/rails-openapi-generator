# frozen_string_literal: true

RSpec.describe RailsOpenapiGenerator::MethodResolver, :rails_app do
  subject(:resolver) { described_class.new }

  let(:controller) { Api::ReportsController }

  it "resolves a method defined in the controller itself" do
    resolved = resolver.resolve(controller, "stream_report")

    expect(resolved.name).to eq("stream_report")
    expect(resolved.node.first).to eq(:def)
    expect(resolved.location).to end_with("reports_controller.rb:#{stream_report_line}")
  end

  it "resolves a method defined in an included concern" do
    resolved = resolver.resolve(controller, "stream_via_concern")

    expect(resolved).not_to be_nil
    expect(resolved.location).to include("concerns/file_streaming.rb")
  end

  it "returns nil for a method that does not exist" do
    expect(resolver.resolve(controller, "no_such_method")).to be_nil
  end

  it "returns nil for a method defined outside the application (a framework method)" do
    # send_file is defined in the actionpack gem, not the app.
    expect(resolver.resolve(controller, "send_file")).to be_nil
  end

  it "returns nil when given no controller class" do
    expect(resolver.resolve(nil, "stream_report")).to be_nil
  end

  def stream_report_line
    file = File.expand_path("../fixtures/dummy/app/controllers/api/reports_controller.rb", __dir__)
    File.readlines(file).index { |line| line.include?("def stream_report") } + 1
  end
end
