# frozen_string_literal: true

RSpec.describe "Deterministic output", :rails_app do
  it "produces byte-identical output across runs of unchanged input (SC-008)" do
    paths = Array.new(2) do |index|
      output = File.expand_path("../../tmp/spec/determinism_#{index}.json", __dir__)
      config = RailsOpenapiGenerator::Configuration.new
      config.output_path = output
      RailsOpenapiGenerator::Generator.new(config).generate
      output
    end

    expect(File.read(paths[0])).to eq(File.read(paths[1]))
  ensure
    FileUtils.rm_rf(File.expand_path("../../tmp/spec", __dir__))
  end
end
