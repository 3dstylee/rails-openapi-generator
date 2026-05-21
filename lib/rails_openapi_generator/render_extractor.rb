# frozen_string_literal: true

module RailsOpenapiGenerator
  # The result of inspecting an action body for inline response signals.
  #
  # One `render json:`, `head`, or template-render call located somewhere
  # in the reachable code (action body or, later, a helper / before_action
  # body). `explicit_status` is the call's `status:` option / `head`
  # argument when set, or `nil` for a status-less render (the HTTP-method
  # convention is applied downstream in {ResponseBuilder}). `schema` is the
  # OpenAPI schema derived from a literal `render json:` value, or `nil` for
  # a non-literal value, a `head`, an unresolved template, or a template
  # whose view does not exist.
  #
  # `source` is `:action`, `:helper`, or `:before_action` — kept for
  # diagnostics; not emitted to the document.
  #
  # `template_name` (feature 011) is the template path for an unresolved
  # `render "path"` / `render :symbol` / `render template:` / `render action:`
  # call; nil for JSON-render and head sites and for template sites already
  # resolved by the Generator. `format_hint` (feature 011) is the literal
  # value of the render's `formats:` option (Symbol or non-empty
  # Array<Symbol>); nil when the option is absent or non-literal.
  # `kind_hint` (feature 011) is `:html_page` when a resolved template site
  # points at an HTML view; nil otherwise.
  RenderSite = Struct.new(
    :explicit_status, :schema, :head, :source,
    :template_name, :format_hint, :kind_hint, :content_type,
    keyword_init: true
  ) do
    def head?
      head
    end

    def template?
      !template_name.nil?
    end

    def html_template?
      kind_hint == :html_page
    end
  end

  # `renders_json` is true when the action contains a happy-path `render json:`.
  # `explicit_status` is the last happy-path (2xx/3xx) status the action sets
  # via `head` or `render status:`, or nil. `head` is true when the action's
  # success path is a `head` call (a body-less response). `redirect_status` is
  # the last 3xx status from a `redirect_to` / `redirect_back` /
  # `redirect_back_or_to` call (default 302 when no `status:` option is set),
  # or nil when no redirect is present. `render_sites` is every `render json:`
  # and `head` reachable from the action — used by {ResponseBuilder} to build
  # the multi-status response set (feature 010).
  RenderResult = Struct.new(
    :schema, :renders_json, :explicit_status, :head, :file_download, :html_inline, :template,
    :redirect_status, :render_sites,
    keyword_init: true
  ) do
    def head?
      head
    end
  end

  # Extracts response signals from an action body: a happy-path literal
  # `render json:`, the explicit success status (from `head` and
  # `render status:`), a `send_file`/`send_data` download, a `render html:`,
  # and an explicitly rendered template name. Renders carrying an error status
  # (4xx/5xx) are ignored for the JSON value and the explicit status.
  class RenderExtractor
    HAPPY_STATUS = (200..399)
    REDIRECT_STATUS = (300..399)
    REDIRECT_METHODS = %w[redirect_to redirect_back redirect_back_or_to].freeze
    DEFAULT_REDIRECT_STATUS = 302
    # `respond_to` format symbols mapped to OpenAPI content types (feature 012).
    # Symbols not in this map are silently ignored. A future feature MAY extend it.
    FORMAT_CONTENT_TYPES = { "json" => "application/json", "html" => "text/html" }.freeze
    # Placeholder template-name used by a bare `format.<symbol>` gate. The
    # Generator's resolve_template_sites! pass swaps this for the action's
    # default view (`<controller>/<action>`) before view lookup runs.
    SENTINEL_DEFAULT_VIEW = "__rog_default_view__"
    # Sentinel meaning "no happy-path `render json:` was found".
    NONE = :__rog_no_render__

    # Rails status symbols → numeric codes, enough to classify happy vs. error.
    STATUS_CODES = {
      ok: 200, created: 201, accepted: 202, non_authoritative_information: 203,
      no_content: 204, reset_content: 205, partial_content: 206,
      multiple_choices: 300, moved_permanently: 301, found: 302, see_other: 303,
      not_modified: 304, temporary_redirect: 307, permanent_redirect: 308,
      bad_request: 400, unauthorized: 401, payment_required: 402, forbidden: 403,
      not_found: 404, method_not_allowed: 405, not_acceptable: 406,
      request_timeout: 408, conflict: 409, gone: 410, precondition_failed: 412,
      payload_too_large: 413, unsupported_media_type: 415, im_a_teapot: 418,
      unprocessable_entity: 422, unprocessable_content: 422, locked: 423,
      too_many_requests: 429, internal_server_error: 500, not_implemented: 501,
      bad_gateway: 502, service_unavailable: 503, gateway_timeout: 504
    }.freeze

    # Returns a {RenderResult} for the given {ActionSource}.
    def extract(action_source)
      node = action_source&.method_node
      return empty_result if node.nil?

      renders    = collect_renders(node)
      json_value = happy_render_json_value(renders)

      RenderResult.new(
        schema: schema_for(json_value),
        renders_json: !json_value.equal?(NONE),
        explicit_status: explicit_status(node, renders),
        head: happy_head?(node),
        file_download: file_download?(node),
        html_inline: renders.any? { |render| render[:options].key?(:html) },
        template: template_name(renders),
        redirect_status: redirect_status(node),
        render_sites: render_sites(node, renders, source: :action)
      )
    end

    # Collects render-sites from an extra body (e.g. a helper method or a
    # `before_action` callback) and returns them tagged with `source`.
    def collect_sites(node, source:)
      return [] if node.nil?

      render_sites(node, collect_renders(node), source: source)
    end

    private

    def empty_result
      RenderResult.new(
        schema: nil, renders_json: false, explicit_status: nil, head: false,
        file_download: false, html_inline: false, template: nil, redirect_status: nil,
        render_sites: []
      )
    end

    # Every `render json:`, `head`, and template-render call in `node`,
    # returned as a list of {RenderSite}s in source order. Renders carrying
    # a non-2xx/3xx status are kept (the caller decides what to do with
    # them per status); renders whose `status:` symbol is unmapped are
    # dropped (R7). Template sites are emitted unresolved — the Generator
    # resolves them to a view at orchestration time (feature 011 R4).
    def render_sites(node, renders, source:)
      json_sites = renders.filter_map { |render| json_site(render, source) }
      template_sites = renders.filter_map { |render| template_site(render, source) }
      head_sites = head_sites(node, source)
      gate_sites = respond_to_gate_sites(node, source)
      json_sites + template_sites + head_sites + gate_sites
    end

    def json_site(render, source)
      return nil unless render[:options].key?(:json)

      raw_status = render[:options][:status]
      explicit = raw_status.nil? ? nil : status_code(raw_status)
      return nil if raw_status && explicit.nil? # unmapped symbol → drop site

      value = render[:options][:json]
      schema = value.equal?(LiteralEvaluator::UNRESOLVED) ? nil : LiteralEvaluator.schema_for(value)
      RenderSite.new(explicit_status: explicit, schema: schema, head: false, source: source)
    end

    # An unresolved template-render site: `render "path"`, `render :symbol`,
    # `render template: "..."`, or `render action: :name`. Excludes renders
    # that carry a `:json` or `:html` option (those are handled elsewhere).
    def template_site(render, source)
      options = render[:options]
      return nil if options.key?(:json) || options.key?(:html)

      name = explicit_template_name(render)
      return nil if name.nil?

      raw_status = options[:status]
      explicit = raw_status.nil? ? nil : status_code(raw_status)
      return nil if raw_status && explicit.nil? # unmapped status symbol → drop

      RenderSite.new(
        explicit_status: explicit, schema: nil, head: false, source: source,
        template_name: name, format_hint: format_hint_of(options)
      )
    end

    # The literal value of `options[:formats]`, normalized to a Symbol or a
    # non-empty Array<Symbol>; nil otherwise (non-literal → "no hint").
    # `LiteralEvaluator` evaluates Symbol literals to Strings, so we accept
    # both String and Symbol and normalize via `to_sym`.
    def format_hint_of(options)
      value = options[:formats]
      return nil if value.equal?(LiteralEvaluator::UNRESOLVED) || value.nil?
      return value.to_sym if value.is_a?(String) || value.is_a?(Symbol)
      return nil unless value.is_a?(Array)

      symbols = value.filter_map { |element| element.to_sym if element.is_a?(String) || element.is_a?(Symbol) }
      symbols.empty? ? nil : symbols
    end

    def head_sites(node, source)
      render_calls(node, "head").map do |args|
        RenderSite.new(explicit_status: head_status(args), schema: nil, head: true, source: source)
      end
    end

    # `respond_to do |fmt| fmt.json; fmt.html { ... }; end` — for each
    # mapped `<param>.<format>` call inside the block, build a format-gate
    # site contributing a content type to the operation's response set.
    # Unmapped formats (`format.xml`, `format.any`, etc.) are skipped.
    def respond_to_gate_sites(node, source)
      sites = []
      respond_to_blocks(node).each do |block_node|
        param_name = block_param_name(block_node)
        next if param_name.nil?

        body = do_or_brace_body(block_node)
        next if body.nil?

        collect_format_gates(body, param_name, source, sites)
      end
      sites
    end

    # Every `respond_to do |...| ... end` (or `{|...|...}`) block in the
    # subtree. Returns the `:do_block` / `:brace_block` AST nodes.
    def respond_to_blocks(node, found = [])
      return found unless node.is_a?(Array)

      if node[0] == :method_add_block
        call_node = node[1]
        if fcall_named?(call_node, "respond_to") || method_add_arg_named?(call_node, "respond_to")
          block_node = node[2]
          found << block_node if block_node.is_a?(Array) && %i[do_block brace_block].include?(block_node[0])
        end
      end
      node.each { |child| respond_to_blocks(child, found) if child.is_a?(Array) }
      found
    end

    def fcall_named?(node, name)
      node.is_a?(Array) && node[0] == :fcall && ident?(node[1], name)
    end

    def method_add_arg_named?(node, name)
      return false unless node.is_a?(Array) && node[0] == :method_add_arg

      fcall_named?(node[1], name)
    end

    # `[:do_block, [:block_var, [:params, [[:@ident, NAME, ...]], ...]], ...]`
    # or `[:brace_block, [:block_var, ...], ...]`. Returns NAME or nil.
    def block_param_name(block_node)
      var_node = block_node[1]
      return nil unless var_node.is_a?(Array) && var_node[0] == :block_var

      params = var_node[1]
      return nil unless params.is_a?(Array) && params[0] == :params

      first_param = Array(params[1]).first
      return nil unless first_param.is_a?(Array) && first_param[0] == :@ident

      first_param[1]
    end

    # Returns the statement list inside the block body, or nil.
    def do_or_brace_body(block_node)
      case block_node[0]
      when :do_block
        bodystmt = block_node[2]
        bodystmt.is_a?(Array) && bodystmt[0] == :bodystmt ? bodystmt[1] : nil
      when :brace_block
        block_node[2]
      end
    end

    # Walks `body` for `<param>.<format>` calls (with or without a body
    # block) and builds a gate site per mapped format. Skips nested
    # `:def`/`:defs` subtrees so a `respond_to` inside a nested method
    # definition (rare) is handled by its own outer pass. When a node
    # matches as a gate, recursion does NOT descend into its children
    # — otherwise a `:method_add_block` gate would emit twice (once for
    # the outer block-bearing call, again for the inner bare `:call`).
    def collect_format_gates(body, param_name, source, sites)
      return unless body.is_a?(Array)

      gate = format_call_gate(body, param_name)
      if gate
        append_gate_sites(gate, source, sites)
        return
      end

      body.each do |child|
        next unless child.is_a?(Array)
        next if %i[def defs].include?(child[0])

        collect_format_gates(child, param_name, source, sites)
      end
    end

    # If `node` is a `:call` to `<param>.<format>` (optionally wrapped in
    # `:method_add_block` with a body block), returns
    # `{ format: <symbol>, content_type: <ct>, body: <block_body_or_nil> }`;
    # otherwise nil. Unmapped formats return nil.
    def format_call_gate(node, param_name)
      block_body = nil
      call_node = node

      if node[0] == :method_add_block
        call_node = node[1]
        inner = node[2]
        block_body = do_or_brace_body(inner) if inner.is_a?(Array)
      end

      return nil unless call_node.is_a?(Array) && call_node[0] == :call

      receiver = call_node[1]
      return nil unless var_ref_named?(receiver, param_name)

      method_node = call_node[3]
      return nil unless method_node.is_a?(Array) && method_node[0] == :@ident

      format = method_node[1]
      content_type = FORMAT_CONTENT_TYPES[format]
      return nil if content_type.nil?

      { format: format, content_type: content_type, body: block_body }
    end

    def var_ref_named?(node, name)
      node.is_a?(Array) && node[0] == :var_ref && node[1].is_a?(Array) &&
        node[1][0] == :@ident && node[1][1] == name
    end

    # Builds sites for one gate. If the gate has a body block containing
    # render/head calls, those sites carry the gate's content_type;
    # otherwise emit a single unresolved default-view template site.
    def append_gate_sites(gate, source, sites)
      block_body = gate[:body]

      if block_body
        nested_renders = collect_renders(block_body)
        nested = render_sites(block_body, nested_renders, source: source)
        nested.each { |site| site.content_type = gate[:content_type] }
        if nested.any?
          sites.concat(nested)
          return
        end
      end

      sites << RenderSite.new(
        explicit_status: nil, schema: nil, head: false, source: source,
        template_name: SENTINEL_DEFAULT_VIEW, format_hint: gate[:format].to_sym,
        content_type: gate[:content_type]
      )
    end

    def schema_for(json_value)
      return nil if json_value.equal?(NONE) || json_value == LiteralEvaluator::UNRESOLVED

      LiteralEvaluator.schema_for(json_value)
    end

    # Each `render` call → { options: Hash, positionals: [arg nodes], code: }.
    def collect_renders(node)
      render_calls(node, "render").map do |args|
        options     = {}
        positionals = []
        args.each do |arg|
          if arg.is_a?(Array) && arg[0] == :bare_assoc_hash
            evaluated = LiteralEvaluator.evaluate(arg)
            options = evaluated if evaluated.is_a?(Hash)
          else
            positionals << arg
          end
        end
        { options: options, positionals: positionals, code: status_code(options[:status]) }
      end
    end

    # The `json:` value of the last `render json:` that is not an error render.
    def happy_render_json_value(renders)
      json  = renders.select { |render| render[:options].key?(:json) }
      happy = json.reject { |render| render[:code] && render[:code] >= 400 }
      happy.empty? ? NONE : happy.last[:options][:json]
    end

    def file_download?(node)
      render_calls(node, "send_file").any? || render_calls(node, "send_data").any?
    end

    # The name of the last explicitly rendered template (not a json/html render).
    def template_name(renders)
      renders.reverse_each do |render|
        next if render[:options].key?(:json) || render[:options].key?(:html)

        name = explicit_template_name(render)
        return name if name
      end
      nil
    end

    def explicit_template_name(render)
      options = render[:options]
      return options[:template] if options[:template].is_a?(String)
      return options[:action].to_s if options[:action]

      render[:positionals].each do |arg|
        value = LiteralEvaluator.evaluate(arg)
        return value if value.is_a?(String) # render "path" or render :action
      end
      nil
    end

    def status_code(value)
      case value
      when nil     then 200
      when Integer then value
      when String  then STATUS_CODES[value.to_sym]
      end
    end

    # The last happy-path (2xx/3xx) status the action sets explicitly, or nil.
    def explicit_status(node, renders)
      codes = render_status_codes(renders) + head_status_codes(node)
      codes.select { |code| HAPPY_STATUS.cover?(code) }.last
    end

    def render_status_codes(renders)
      renders.filter_map { |render| render[:code] if render[:options].key?(:status) }
    end

    def head_status_codes(node)
      render_calls(node, "head").filter_map { |args| head_status(args) }
    end

    # The status code of a `head` call; `head` with no argument defaults to 200.
    def head_status(args)
      return 200 if args.empty?

      status_code(LiteralEvaluator.evaluate(args.first))
    end

    # True when the action has a `head` call with a happy-path (2xx/3xx) status.
    def happy_head?(node)
      head_status_codes(node).any? { |code| HAPPY_STATUS.cover?(code) }
    end

    # The last 3xx status from a `redirect_to` / `redirect_back` /
    # `redirect_back_or_to` call, or nil when no such redirect is present.
    # A redirect call with no `status:` option defaults to 302; one whose
    # symbol is unmapped also defaults to 302; one whose `status:` resolves
    # to a non-3xx code is ignored (treated as not a redirect signal).
    def redirect_status(node)
      codes = REDIRECT_METHODS.flat_map { |name| redirect_codes(node, name) }
      codes.select { |code| REDIRECT_STATUS.cover?(code) }.last
    end

    def redirect_codes(node, name)
      render_calls(node, name).map { |args| redirect_status_from_args(args) }
    end

    def redirect_status_from_args(args)
      args.each do |arg|
        next unless arg.is_a?(Array) && arg[0] == :bare_assoc_hash

        options = LiteralEvaluator.evaluate(arg)
        next unless options.is_a?(Hash) && options.key?(:status)

        return status_code(options[:status]) || DEFAULT_REDIRECT_STATUS
      end
      DEFAULT_REDIRECT_STATUS
    end

    # Collects the argument-array of every `<name>` command call in the subtree.
    def render_calls(node, name, found = [])
      return found unless node.is_a?(Array)
      return found if respond_to_block_subtree?(node)

      args = command_args(node, name)
      found << args if args

      node.each { |child| render_calls(child, name, found) if child.is_a?(Array) }
      found
    end

    # True when `node` is a `:method_add_block` whose call is `respond_to`
    # — the subtree's renders / heads belong to format gates and are
    # collected by `respond_to_gate_sites`, not by the top-level pass.
    def respond_to_block_subtree?(node)
      return false unless node[0] == :method_add_block

      call = node[1]
      fcall_named?(call, "respond_to") || method_add_arg_named?(call, "respond_to")
    end

    def command_args(node, name)
      case node[0]
      when :command
        ident?(node[1], name) ? args_list(node[2]) : nil
      when :method_add_arg
        inner = node[1]
        return nil unless inner.is_a?(Array) && inner[0] == :fcall && ident?(inner[1], name)

        paren = node[2]
        paren.is_a?(Array) && paren[0] == :arg_paren ? args_list(paren[1]) : nil
      end
    end

    def args_list(node)
      node.is_a?(Array) && node[0] == :args_add_block ? Array(node[1]) : []
    end

    def ident?(node, name)
      node.is_a?(Array) && node[0] == :@ident && node[1] == name
    end
  end
end
