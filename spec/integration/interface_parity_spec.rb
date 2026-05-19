# frozen_string_literal: true

require "json"
require "rake"
require "stringio"

RSpec.describe "Interface parity: library, rake task, and CLI", :rails_app do
  let(:tmp_dir) { File.expand_path("../../tmp/spec", __dir__) }

  before { FileUtils.mkdir_p(tmp_dir) }
  after  { FileUtils.rm_rf(tmp_dir) }

  def library_document
    config = RailsOpenapiGenerator::Configuration.new
    config.output_path = File.join(tmp_dir, "library.json")
    RailsOpenapiGenerator::Generator.new(config).generate
    JSON.parse(File.read(config.output_path))
  end

  def cli_document
    path = File.join(tmp_dir, "cli.json")
    code = RailsOpenapiGenerator::CLI.start(
      ["--rails-root", DummyApp::ROOT, "--output", path],
      stdout: StringIO.new, stderr: StringIO.new
    )
    expect(code).to eq(0)
    JSON.parse(File.read(path))
  end

  def rake_document
    path = File.join(tmp_dir, "rake.json")
    previous = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load File.expand_path("../../lib/tasks/rails_openapi_generator.rake", __dir__)
    RailsOpenapiGenerator.configuration.output_path = path
    Rake.application["openapi:generate"].invoke
    JSON.parse(File.read(path))
  ensure
    Rake.application = previous
  end

  it "the CLI produces the same document as the library API" do
    expect(cli_document).to eq(library_document)
  end

  it "the rake task produces the same document as the library API" do
    expect(rake_document).to eq(library_document)
  end
end
