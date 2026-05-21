# frozen_string_literal: true

module Api
  # Exercises feature 018: a render whose status (and body) depend on
  # method parameters is recovered when the call site passes literal
  # arguments. The three actions cover positional binding, multi-level
  # propagation, and keyword binding.
  class BindingHelpersController < ApplicationController
    # US1: rescue clause calls a helper with positional literals.
    def create
      param! :name, String, required: true
      render_success({ ok: true })
    rescue StandardError
      render_error("oops", 422, :unprocessable_entity)
    end

    # US2: a two-level helper chain forwards the literal status.
    def chain
      outer_helper(:created)
    end

    # US3: kwarg call site, kwarg-bound helper.
    def kwargs
      respond(json: { ok: true }, status: :accepted)
    end

    private

    def render_success(payload)
      render json: payload, status: :ok
    end

    def render_error(message, status_code, status)
      render json: { response: {}, message: message, status_code: status_code }, status: status
    end

    def outer_helper(status)
      inner_helper(status)
    end

    def inner_helper(status)
      head status
    end

    def respond(json:, status:)
      render json: json, status: status
    end
  end
end
