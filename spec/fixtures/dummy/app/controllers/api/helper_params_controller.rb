# frozen_string_literal: true

module Api
  class HelperParamsController < ApplicationController
    # param! calls declared only in a private helper.
    def update
      validate_update_params!
      head :no_content
    end

    # The same helper reached through another one: chained -> validate_chain -> validate_update_params!.
    def chained
      validate_chain
      head :no_content
    end

    # The action and a helper both declare :query; the action's declaration wins.
    def search
      param! :query, String, description: "Declared in the action"
      validate_search_params!
      head :ok
    end

    private

    def validate_update_params!
      param! :id, Integer, required: true
      param! :title, String, description: "Title of the record"
    end

    def validate_chain
      validate_update_params!
    end

    def validate_search_params!
      param! :query, String, description: "Declared in the helper"
    end
  end
end
