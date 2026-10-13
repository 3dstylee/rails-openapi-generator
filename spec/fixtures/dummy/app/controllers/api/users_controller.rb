# frozen_string_literal: true

module Api
  class UsersController < ApplicationController
    # Search users
    # Returns the users matching the given filters, newest first.
    def index
      param! :query, String, blank: false, description: "Free-text search across name and email"
      param! :per_page, Integer, in: 1..100
    end

    # Show a user
    def show
      param! :id, Integer, required: true
    end

    def create
      param! :name, String, required: true, description: "Display name. 1–100 chars."
      param! :email, String, required: true, format: /.+@.+/
      # Split with a trailing backslash on purpose: covers adjacent string literals.
      param! :role, String, in: %w[admin member],
                            description: "Account role. Admins can manage " \
                                         "other users."
      return render status: :unprocessable_entity, json: { error: "invalid" } unless params[:name]

      render json: { id: 1, role: "member", active: true }
    end

    # Delete a user
    def destroy
      param! :id, Integer, required: true
      head :no_content
    end
  end
end
