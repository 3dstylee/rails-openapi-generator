# frozen_string_literal: true

module Api
  # Exercises feature 020: JSON Schema sidecar files.
  class SidecarsController < ApplicationController
    # US1: a template that references a partial with a sidecar. The
    # partial's sidecar overrides the parser's inference.
    def with_partial; end

    # US2 (template-backed): an inline render whose response schema is
    # overridden by a sidecar at the conventional view path.
    def inline_render
      render json: { status: "ok" }
    end

    # US2 (no view): no template, no inline render — Rails returns an
    # implicit empty response. The sidecar at the conventional view
    # path documents the response anyway.
    def no_view; end

    # US3 (resilience): a malformed sidecar must not abort the run.
    # The action's inline render schema is documented; a warning is
    # emitted about the malformed file.
    def malformed
      render json: { ok: true }
    end
  end
end
