# frozen_string_literal: true

require "ripper"

RSpec.describe RailsOpenapiGenerator::HelperBindingWalker do
  # The walker delegates method lookup to a MethodResolver. A fake
  # resolver mapping method names to their parsed `:def` nodes keeps
  # these specs focused on binding + substitution + recursion behavior,
  # independent of file-system / Rails-class lookup.
  let(:resolver) { fake_resolver(method_defs) }
  let(:controller_class) { :fake_controller }
  let(:walker) { described_class.new(method_resolver: resolver, max_depth: 5) }
  let(:method_defs) { {} }

  def parse_def(source)
    program = Ripper.sexp(source)
    program && program[1].find { |node| node.is_a?(Array) && node[0] == :def }
  end

  def fake_resolver(defs)
    Struct.new(:defs) do
      def resolve(_controller_class, name)
        node = defs[name.to_s]
        node && RailsOpenapiGenerator::ResolvedMethod.new(name: name, node: node, location: "fake:#{name}")
      end
    end.new(defs)
  end

  def render_status(body)
    statements = body[1]
    render = statements.find do |stmt|
      stmt.is_a?(Array) && stmt[0] == :command &&
        stmt[1].is_a?(Array) && stmt[1][1] == "render"
    end
    return nil if render.nil?

    hash = render[2][1].first
    return nil unless hash.is_a?(Array) && hash[0] == :bare_assoc_hash

    Array(hash[1]).each do |pair|
      label = pair[1]
      next unless label.is_a?(Array) && label[0] == :@label && label[1] == "status:"

      return pair[2]
    end
    nil
  end

  describe "positional argument binding (US1)" do
    let(:method_defs) do
      {
        "render_error" => parse_def(<<~RUBY)
          def render_error(message, status_code, status)
            render json: { message: message }, status: status
          end
        RUBY
      }
    end

    it "binds positional literals into the helper body and returns one substituted body" do
      action_node = parse_def(<<~RUBY)
        def create
          render_error("oops", 422, :unprocessable_entity)
        end
      RUBY

      bodies = walker.reachable_bodies(controller_class, action_node)

      expect(bodies.size).to eq(1)
      status_node = render_status(bodies.first)
      # The bound :unprocessable_entity literal replaces the `var_ref` to `status`.
      expect(status_node[0]).to eq(:symbol_literal)
    end
  end

  describe "multi-level propagation (US2)" do
    let(:method_defs) do
      {
        "outer_helper" => parse_def(<<~RUBY),
          def outer_helper(status)
            inner_helper(status)
          end
        RUBY
        "inner_helper" => parse_def(<<~RUBY)
          def inner_helper(status)
            render json: {}, status: status
          end
        RUBY
      }
    end

    it "propagates the outer literal into the inner helper's body" do
      action_node = parse_def(<<~RUBY)
        def create
          outer_helper(:created)
        end
      RUBY

      bodies = walker.reachable_bodies(controller_class, action_node)

      # outer_helper's body + inner_helper's body — both substituted.
      expect(bodies.size).to eq(2)
      inner_status = render_status(bodies.last)
      expect(inner_status[0]).to eq(:symbol_literal)
    end
  end

  describe "keyword argument binding (US3)" do
    let(:method_defs) do
      {
        "respond" => parse_def(<<~RUBY)
          def respond(json:, status:)
            render json: json, status: status
          end
        RUBY
      }
    end

    it "binds kwargs by name" do
      action_node = parse_def(<<~RUBY)
        def create
          respond(json: { ok: true }, status: :created)
        end
      RUBY

      bodies = walker.reachable_bodies(controller_class, action_node)

      expect(bodies.size).to eq(1)
      status_node = render_status(bodies.first)
      expect(status_node[0]).to eq(:symbol_literal)
    end
  end

  describe "non-literal arguments" do
    let(:method_defs) do
      {
        "render_error" => parse_def(<<~RUBY)
          def render_error(message, status)
            render json: { message: message }, status: status
          end
        RUBY
      }
    end

    it "still substitutes the literal arg, leaving the non-literal arg's var_ref untouched" do
      action_node = parse_def(<<~RUBY)
        def create
          render_error(e.message, 422)
        end
      RUBY

      bodies = walker.reachable_bodies(controller_class, action_node)

      expect(bodies.size).to eq(1)
      status_node = render_status(bodies.first)
      expect(status_node[0]).to eq(:@int) # 422 substituted in for `status`
    end
  end

  describe "max depth termination" do
    let(:method_defs) do
      {
        "loop_a" => parse_def(<<~RUBY),
          def loop_a
            loop_b
          end
        RUBY
        "loop_b" => parse_def(<<~RUBY)
          def loop_b
            loop_a
          end
        RUBY
      }
    end

    it "terminates a cyclic helper chain at max_depth" do
      action_node = parse_def("def create; loop_a; end")

      bodies = walker.reachable_bodies(controller_class, action_node)

      # 5 levels of recursion (max_depth=5) — exact count is bounded; the
      # important property is that the walk does not blow up.
      expect(bodies.size).to be <= 6
    end
  end

  describe "no helper calls" do
    it "returns an empty list when the root has no receiverless calls to known helpers" do
      action_node = parse_def("def create; head :ok; end")
      expect(walker.reachable_bodies(controller_class, action_node)).to eq([])
    end

    it "returns an empty list when given a nil root or nil controller class" do
      expect(walker.reachable_bodies(controller_class, nil)).to eq([])
      expect(walker.reachable_bodies(nil, parse_def("def create; head :ok; end"))).to eq([])
    end
  end

  describe "root exclusion" do
    let(:method_defs) do
      { "helper" => parse_def("def helper; head :ok; end") }
    end

    it "does NOT include the root node in returned bodies" do
      root = parse_def("def create; helper; end")
      bodies = walker.reachable_bodies(controller_class, root)

      expect(bodies.size).to eq(1)
      expect(bodies.first).not_to equal(root)
    end
  end
end
