# frozen_string_literal: true

module Api
  class UsersController < ApplicationController
    # Search users
    # Returns the users matching the given filters, newest first.
    def index
      param! :query, String, blank: false
      param! :per_page, Integer, in: 1..100
      render json: []
    end

    # Show a user
    def show
      param! :id, Integer, required: true
      render json: {}
    end

    def create
      param! :name, String, required: true
      param! :email, String, required: true, format: /.+@.+/
      param! :role, String, in: %w[admin member]
      render json: {}
    end
  end
end
