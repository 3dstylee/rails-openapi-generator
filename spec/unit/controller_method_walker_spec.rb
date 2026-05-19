# frozen_string_literal: true

RSpec.describe RailsOpenapiGenerator::ControllerMethodWalker, :rails_app do
  let(:controller) { Api::ReportsController }

  let(:actions) do
    file = File.expand_path("../fixtures/dummy/app/controllers/api/reports_controller.rb", __dir__)
    RailsOpenapiGenerator::YardParser.new.parse(file)
  end

  def node(action)
    actions[action].method_node
  end

  def walker(max_depth: 5)
    described_class.new(method_resolver: RailsOpenapiGenerator::MethodResolver.new, max_depth: max_depth)
  end

  it "returns the action body itself" do
    bodies = walker.reachable_bodies(controller, node("single"))
    expect(bodies).to include(node("single"))
  end

  it "reaches a helper the action calls" do
    bodies = walker.reachable_bodies(controller, node("single"))
    # `single` calls `stream_report`, which contains `send_file`.
    send_file_calls = bodies.flat_map { |b| described_class.receiverless_call_names(b) }
    expect(send_file_calls).to include("send_file")
  end

  it "reaches a chain of helpers" do
    bodies = walker.reachable_bodies(controller, node("chained"))
    calls = bodies.flat_map { |b| described_class.receiverless_call_names(b) }
    expect(calls).to include("deliver", "stream_report", "send_file")
  end

  it "does not loop on cyclic helper methods" do
    expect { walker.reachable_bodies(controller, node("cyclic")) }.not_to raise_error
  end

  it "stops collecting beyond the configured maximum depth" do
    shallow = walker(max_depth: 1)
    calls = shallow.reachable_bodies(controller, node("chained"))
                   .flat_map { |b| described_class.receiverless_call_names(b) }
    # `chained` -> `deliver` (depth 1) is reached; `stream_report` (depth 2) is not.
    expect(calls).to include("deliver")
    expect(calls).not_to include("send_file")
  end

  it "returns an empty array for a nil action node" do
    expect(walker.reachable_bodies(controller, nil)).to eq([])
  end
end
