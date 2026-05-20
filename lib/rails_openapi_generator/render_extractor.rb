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
    :template_name, :format_hint, :kind_hint,
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
      json_sites + template_sites + head_sites
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

      args = command_args(node, name)
      found << args if args

      node.each { |child| render_calls(child, name, found) if child.is_a?(Array) }
      found
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
