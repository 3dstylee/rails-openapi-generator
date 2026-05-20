# frozen_string_literal: true

require "json"
require "set"

module RailsOpenapiGenerator
  # Assembles an operation's success {Response} from a {Classification}.
  #
  # For `:json` operations, builds the multi-entry response set (feature
  # 010): every reachable `render json:` / `head` call contributes one
  # entry keyed by its status; same-status entries collapse per FR-004 /
  # FR-005 (identical schemas dedup; distinct schemas union into
  # `oneOf` sorted by canonical JSON; head's no-body contribution drops
  # when any render at the same status carries a known body).
  #
  # For `:redirect`, `:html_page`, `:file_download`, builds a single-entry
  # Response — these kinds are unchanged by the multi-status feature.
  class ResponseBuilder
    STATUS_BY_METHOD = { "GET" => 200, "PUT" => 200, "PATCH" => 200, "POST" => 201, "DELETE" => 204 }.freeze
    DEFAULT_STATUS = 200

    # `classification` is a {Classification}; `view_schema` is the parsed
    # jbuilder schema Hash for a JSON endpoint resolved via a view, or nil.
    # `extra_sites` is an optional list of {RenderSite}s reached through
    # helper methods or before_action callbacks (feature 010 US2/US3).
    def build(route, classification:, view_schema: nil, extra_sites: [])
      render_result = classification.render_result

      case classification.kind
      when :html_page
        Response.new(status: status_for(route, render_result), kind: :html_page,
                     page_reference: classification.template_name)
      when :file_download
        Response.new(status: status_for(route, render_result), kind: :file_download)
      when :redirect
        Response.new(status: render_result.redirect_status, kind: :redirect)
      when :json
        json_response(route, render_result, view_schema, extra_sites)
      else
        undeterminable_response(route, render_result, extra_sites)
      end
    end

    private

    # The explicit status the action sets, falling back to the HTTP-method
    # convention when the action sets none.
    def status_for(route, render_result)
      render_result.explicit_status || STATUS_BY_METHOD.fetch(route.http_method, DEFAULT_STATUS)
    end

    # A multi-entry JSON Response. Sites from the action plus extras
    # (helpers / before_action) are grouped by status and unioned.
    def json_response(route, render_result, view_schema, extra_sites)
      sites = Array(render_result.render_sites) + Array(extra_sites)
      entries = entries_from_sites(sites, route)

      # No render sites: fall back to single-entry under the method
      # convention, with the view's schema (if any) or undeterminable.
      if entries.empty?
        status = status_for(route, render_result)
        return Response.new(status: status) if empty_body_path?(render_result) || status == 204

        body = view_schema
        return Response.new(status: status, undeterminable: true) if body.nil?

        return Response.new(status: status, body: body)
      end

      # If only one render site exists, also fall back to the view
      # schema when the site's render is non-literal (preserves the
      # pre-0.9.0 behavior for jbuilder-backed endpoints).
      maybe_use_view(entries, sites, view_schema)
      Response.new(entries: entries, kind: :json)
    end

    # A response is body-less without being undeterminable when the
    # action's only signal is `head` or its explicit status is 204.
    def empty_body_path?(render_result)
      render_result.head? || render_result.explicit_status == 204
    end

    # When the action itself is "undeterminable" (no render_json, no view, no
    # redirect/file/html) but extras (before_action or helper renders)
    # contribute JSON entries, document the operation with the union of
    # the action's own status (a head or convention status, body-less) plus
    # the extras' entries. With no extras, falls back to the legacy single-
    # entry undeterminable Response.
    def undeterminable_response(route, render_result, extra_sites)
      sites = Array(render_result.render_sites) + Array(extra_sites)

      if sites.empty?
        empty = empty_body_path?(render_result)
        return Response.new(status: status_for(route, render_result), undeterminable: !empty)
      end

      html_only = html_template_only_response(route, sites)
      return html_only if html_only

      entries = entries_from_sites(sites, route)
      Response.new(entries: entries, kind: :json)
    end

    # When every site is an HTML-template at the same status (no JSON
    # render contributes), the operation classifies as `:html_page`
    # (feature 011 R5 / FR-007). Otherwise nil — the caller falls through
    # to the JSON multi-entry path.
    def html_template_only_response(route, sites)
      return nil unless sites.all?(&:html_template?)

      statuses = sites.map { |site| resolved_status(site, route) }.uniq
      return nil unless statuses.size == 1

      Response.new(status: statuses.first, kind: :html_page)
    end

    # Groups sites by status, applies the union/dedup rules, and returns
    # an ascending-status list of {ResponseEntry}.
    def entries_from_sites(sites, route)
      grouped = sites.group_by { |site| resolved_status(site, route) }
      grouped.keys.sort.map { |status| ResponseEntry.new(status: status, body: union_body(grouped[status])) }
    end

    # The numeric status the site documents under: explicit status if set,
    # otherwise the HTTP-method convention.
    def resolved_status(site, route)
      site.explicit_status || STATUS_BY_METHOD.fetch(route.http_method, DEFAULT_STATUS)
    end

    # The body for one status group, per the union/dedup rules
    # (data-model.md). A head's no-body contribution drops when any
    # render at the same status carries a known body.
    def union_body(group)
      schemas = group.reject(&:head?).map(&:schema)
      known = schemas.compact
      unique = known.uniq
      case unique.size
      when 0 then nil
      when 1 then unique.first
      else
        { "oneOf" => unique.sort_by { |schema| JSON.generate(schema) } }
      end
    end

    # When the single render site at the convention status has no schema
    # and a view template did provide one, prefer the view's schema —
    # preserves jbuilder-backed endpoint output from before 0.9.0.
    def maybe_use_view(entries, sites, view_schema)
      return if view_schema.nil?
      return unless entries.size == 1
      return unless entries.first.body.nil?

      action_sites = sites.select { |site| site.source == :action && !site.head? }
      return unless action_sites.size == 1

      entries.first.body = view_schema
    end
  end
end
