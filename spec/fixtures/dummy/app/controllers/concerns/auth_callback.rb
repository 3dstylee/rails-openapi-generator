# frozen_string_literal: true

module AuthCallback
  extend ActiveSupport::Concern

  included do
    before_action :authenticate
  end

  private

  def authenticate
    return if defined?(current_user) && current_user

    render json: { error: "unauthorized" }, status: :unauthorized
  end
end
