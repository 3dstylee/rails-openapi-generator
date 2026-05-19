# frozen_string_literal: true

module Api
  class InputsController < ApplicationController
    # GET /api/inputs/:id — reads params[:id] (a path key), params[:query]
    # (a real implicit param), and params[:format] (a Rails-internal key).
    def show
      id     = params[:id]
      filter = params[:query]
      pref   = params[:format]
      render json: { id: id, filter: filter, pref: pref }
    end

    # POST /api/inputs — declares input via strong parameters.
    def create
      params.require(:project)
      params.permit(:name, :archived)
      params.fetch(:token)
      head :ok
    end

    # POST /api/inputs/upload — reads params through a helper method.
    def upload
      store_upload
      head :ok
    end

    private

    def store_upload
      params[:file]
    end
  end
end
