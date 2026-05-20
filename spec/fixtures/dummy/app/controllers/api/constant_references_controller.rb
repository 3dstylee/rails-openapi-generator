# frozen_string_literal: true

module Api
  class ConstantReferencesController < ApplicationController
    # POST — the motivating shape: a top-level `param!` AND a nested
    # `param! :moods, Array do ... end`, both referencing the same
    # constant via `in: ...::MOODS`.
    def execute
      param! :mood, String, required: false,
                            in: AutoPhotoVhs::EnqueueFurnitureGenerationService::MOODS
      param! :moods, Array, required: false, default: [] do |p, i|
        p.param! i, String, required: true,
                            in: AutoPhotoVhs::EnqueueFurnitureGenerationService::MOODS
      end
      head :ok
    end

    # GET — Range constant → minimum / maximum on the parameter schema.
    def range
      param! :page, Integer, in: AutoPhotoVhs::EnqueueFurnitureGenerationService::PAGE_RANGE
      head :ok
    end

    # GET — Regexp constant → pattern on the parameter schema.
    def pattern
      param! :email, String, format: AutoPhotoVhs::EnqueueFurnitureGenerationService::EMAIL_PATTERN
      head :ok
    end

    # GET — Constant resolves but is NOT schema-compatible (a class) → no enum;
    # the "non-literal param!" warning continues to fire for this parameter.
    def non_compatible
      param! :x, String, in: AutoPhotoVhs::EnqueueFurnitureGenerationService::CLASS_REF
      head :ok
    end

    # GET — Constant does not exist → silent NameError rescue; warning still fires.
    def missing
      param! :x, String, in: NotAConstantAtAll # rubocop:disable Lint/UselessConstantScoping
      head :ok
    end
  end
end
