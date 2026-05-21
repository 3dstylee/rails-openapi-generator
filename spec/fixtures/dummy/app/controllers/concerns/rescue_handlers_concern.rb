# frozen_string_literal: true

# Declares an additional rescue_from when included into a controller.
# Verifies (US3) that concern-declared handlers flow through
# `rescue_handlers` and are picked up by the resolver.
module RescueHandlersConcern
  extend ActiveSupport::Concern

  included do
    rescue_from ActionController::ParameterMissing, with: :bad_request_via_concern
  end

  private

  def bad_request_via_concern
    render json: { error: "missing_param" }, status: :bad_request
  end
end
