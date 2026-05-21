# frozen_string_literal: true

module Api
  class RedirectsController < ApplicationController
    # POST with a bare `redirect_to` — Rails default is 302.
    def create
      redirect_to "/api/posts"
    end

    # POST that opts into PRG-pattern 303 via `status: :see_other`.
    def transfer
      redirect_to "/api/posts", status: :see_other
    end

    # GET with a literal integer status — 301 Moved Permanently.
    def old_path
      redirect_to "/api/posts", status: 301
    end

    # POST with `redirect_back_or_to` — also defaults to 302.
    def bounce
      redirect_back_or_to "/api/posts"
    end

    # POST that does both: a JSON render and a redirect. JSON precedence wins —
    # the operation must be documented as JSON, not as a redirect.
    def mixed
      return redirect_to("/api/posts") if params[:fallback]

      render json: { ok: true }
    end
  end
end
