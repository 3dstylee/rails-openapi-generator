# frozen_string_literal: true

module Api
  class MultiStatusController < ApplicationController
    include AuthCallback

    before_action :require_admin, only: [:destroy]

    # PATCH — the motivating shape: happy render with a non-literal value,
    # plus an explicit-status error render with a non-literal value. Two
    # entries (200 and 422), no body on either, no warning.
    def update
      if params[:ok]
        render json: build_payload
      else
        render json: { error_messages: error_messages_for(params) }, status: :unprocessable_entity
      end
    end

    # POST — two identical-shape literal renders at the same status. One
    # entry, no oneOf wrapping.
    def dup_same
      if params[:branch]
        render json: { ok: true }
      else
        render json: { ok: true }
      end
    end

    # POST — two distinct literal shapes at the same status. One entry
    # whose body is `oneOf` the two unique schemas, sorted by canonical
    # JSON ascending for determinism.
    def dup_distinct
      if params[:branch]
        render json: { id: 1, name: "x" }
      else
        render json: { id: 2 }
      end
    end

    # POST — head + render at the same status. One entry with the render's
    # body; the head's no-body contribution drops.
    def head_and_render
      if params[:branch]
        head :ok
      else
        render json: { id: 1 }, status: :ok
      end
    end

    # GET — inherits the concern's before_action :authenticate (401).
    def show
      render json: { id: params[:id] }
    end

    # DELETE — inherits the concern's :authenticate (401) AND is targeted
    # by the controller's `before_action :require_admin, only: [:destroy]`
    # (403).
    def destroy
      head :no_content
    end

    private

    def build_payload
      { id: 1 }
    end

    def error_messages_for(params)
      params[:reason] ? [params[:reason]] : []
    end

    def require_admin
      return if defined?(current_user_admin?) && current_user_admin?

      render json: { error: "forbidden" }, status: :forbidden
    end
  end
end
