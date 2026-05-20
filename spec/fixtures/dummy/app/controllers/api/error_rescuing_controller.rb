# frozen_string_literal: true

# Stand-ins so the rescue_from declarations below resolve at
# controller class-load time without requiring the corresponding gems
# (Pundit, ActiveRecord) as dependencies of the dummy app.
module Pundit
end unless defined?(Pundit)
Pundit.const_set(:NotAuthorizedError, Class.new(StandardError)) unless Pundit.const_defined?(:NotAuthorizedError)

module ActiveRecord
end unless defined?(ActiveRecord)
ActiveRecord.const_set(:RecordNotFound, Class.new(StandardError)) unless ActiveRecord.const_defined?(:RecordNotFound)
ActiveRecord.const_set(:RecordInvalid, Class.new(StandardError)) unless ActiveRecord.const_defined?(:RecordInvalid)

module Api
  # Base controller for fixtures exercising feature 014 (rescue_from).
  # Declares three method-form handlers + one block-form handler, and
  # includes a concern that adds another handler (for US3). Existing
  # fixtures inherit from `ApplicationController` directly and stay
  # byte-identical — only controllers inheriting from THIS class gain
  # the new response entries.
  class ErrorRescuingController < ApplicationController
    include RescueHandlersConcern

    rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
    rescue_from Pundit::NotAuthorizedError, with: :forbidden
    rescue_from ActionController::ParameterMissing, with: :handler_bad_request

    rescue_from ActiveRecord::RecordInvalid do |error|
      render json: { errors: error.record.errors }, status: :unprocessable_entity
    end

    private

    def record_not_found
      render json: { error: "not_found" }, status: :not_found
    end

    def forbidden
      render json: { error: "forbidden" }, status: :forbidden
    end

    def handler_bad_request(exception)
      render json: { error: exception.message }, status: :bad_request
    end
  end
end
