# frozen_string_literal: true

RSpec.describe RailsOpenapiGenerator::YardParser do
  subject(:parser) { described_class.new }

  let(:controller_file) do
    File.expand_path("../fixtures/dummy/app/controllers/api/users_controller.rb", __dir__)
  end

  it "exposes an ActionSource for each controller action" do
    actions = parser.parse(controller_file)
    expect(actions.keys).to contain_exactly("index", "show", "create")
  end

  it "captures the YARD docstring for a documented action" do
    actions = parser.parse(controller_file)
    expect(actions["index"].docstring).to include("Search users")
  end

  it "leaves the docstring nil for an undocumented action" do
    actions = parser.parse(controller_file)
    expect(actions["create"].docstring).to be_nil
  end

  it "exposes a Ripper AST node for each action" do
    actions = parser.parse(controller_file)
    expect(actions["index"].method_node.first).to eq(:def)
  end

  it "records the source line of each action definition" do
    actions = parser.parse(controller_file)
    index_line = File.readlines(controller_file).index { |line| line.include?("def index") } + 1
    expect(actions["index"].line).to eq(index_line)
  end

  it "caches results so a file is parsed once" do
    expect(parser.parse(controller_file)).to equal(parser.parse(controller_file))
  end
end
