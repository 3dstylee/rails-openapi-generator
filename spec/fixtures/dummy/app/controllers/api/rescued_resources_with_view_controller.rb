# frozen_string_literal: true

module Api
  # Regression case for the bug found at end-of-feature-014: an action
  # with NO inline render (just instance-variable assignments) backed
  # by a jbuilder view, inheriting from a controller with `rescue_from`
  # declarations. The operation must document BOTH the happy-path 200
  # (from the view) AND the error-status entries (from rescue_from).
  class RescuedResourcesWithViewController < ErrorRescuingController
    def index
      @line_total_item_count = 0
      @available_points = 0
    end
  end
end
