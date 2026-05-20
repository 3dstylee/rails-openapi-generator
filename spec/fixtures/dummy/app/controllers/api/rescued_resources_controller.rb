# frozen_string_literal: true

module Api
  # Inherits from Api::ErrorRescuingController. Every action on this
  # controller gains the inherited rescue_from handlers' response
  # entries (400/403/404/422) on top of its own status.
  class RescuedResourcesController < ErrorRescuingController
    def show
      param! :id, Integer, required: true
      render json: { id: params[:id] }
    end
  end
end
