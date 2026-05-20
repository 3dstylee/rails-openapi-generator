# frozen_string_literal: true

module Api
  # Exercises feature 017: an action with no render, no head, no redirect,
  # and no view template — but inherited rescue_from handlers contribute
  # error-status entries. The operation must still document the implicit
  # happy-path 200 alongside those error entries.
  class SilentWithRescueController < ErrorRescuingController
    def silent_action
      # Intentionally side-effects only — Rails returns implicit empty 200.
      Rails.logger.info("[silent_action] fired")
    end
  end
end
