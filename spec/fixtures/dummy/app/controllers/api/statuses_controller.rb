# frozen_string_literal: true

module Api
  class StatusesController < ApplicationController
    # POST that responds with `head :ok` — should document 200, not 201.
    def mark
      head :ok
    end

    # PUT that responds with `head :ok` — should document 200.
    def unmark
      head :ok
    end

    # POST that renders a body with an explicit :created status.
    def make
      render json: { id: 1 }, status: :created
    end

    # POST with an error-status guard followed by a happy `head :ok`.
    def guarded
      return render json: { error: "invalid" }, status: :unprocessable_entity unless params[:ok]

      head :ok
    end
  end
end
