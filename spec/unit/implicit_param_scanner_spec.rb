# frozen_string_literal: true

require "ripper"

RSpec.describe RailsOpenapiGenerator::ImplicitParamScanner, :rails_app do
  def walker
    RailsOpenapiGenerator::ControllerMethodWalker.new(method_resolver: RailsOpenapiGenerator::MethodResolver.new)
  end

  subject(:scanner) { described_class.new(walker: walker) }

  # Scans a synthetic action body (no controller class, so no helper recursion).
  def scan(source)
    scanner.scan(nil, Ripper.sexp(source))
  end

  describe "params[:key] index access (US1)" do
    it "detects a symbol key" do
      expect(scan("params[:image]")).to eq(["image"])
    end

    it "detects a string key" do
      expect(scan('params["token"]')).to eq(["token"])
    end

    it "skips a non-literal (dynamic) key" do
      expect(scan("params[some_variable]")).to eq([])
    end

    it "skips Rails-internal keys" do
      expect(scan("x = params[:format]; y = params[:controller]")).to eq([])
    end
  end

  describe "strong-params calls (US2)" do
    it "detects require / permit / fetch / dig keys" do
      expect(scan("params.require(:project)")).to eq(["project"])
      expect(scan("params.permit(:name, :email)")).to eq(%w[email name])
      expect(scan("params.fetch(:token)")).to eq(["token"])
      expect(scan("params.dig(:a, :b)")).to eq(%w[a b])
    end

    it "detects keys across a require(...).permit(...) chain" do
      expect(scan("params.require(:user).permit(:name, :role)")).to eq(%w[name role user])
    end
  end

  describe "recursive scanning through helpers (US3)" do
    let(:upload_action) do
      file = File.expand_path("../fixtures/dummy/app/controllers/api/inputs_controller.rb", __dir__)
      RailsOpenapiGenerator::YardParser.new.parse(file)["upload"].method_node
    end

    it "discovers a params key used inside a helper method" do
      # `upload` calls `store_upload`, which reads `params[:file]`.
      expect(scanner.scan(Api::InputsController, upload_action)).to eq(["file"])
    end
  end

  it "returns sorted, de-duplicated names" do
    expect(scan("params[:b]; params[:a]; params[:a]")).to eq(%w[a b])
  end
end
