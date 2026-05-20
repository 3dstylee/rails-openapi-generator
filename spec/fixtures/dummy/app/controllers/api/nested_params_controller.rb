# frozen_string_literal: true

module Api
  class NestedParamsController < ApplicationController
    # POST — US1: Hash with nested scalar fields.
    def search
      param! :q, Hash do |q|
        q.param! :keyword, String
        q.param! :page, Integer, in: 1..100
      end
      head :ok
    end

    # POST — US2: Array with nested item declaration (no constant).
    def tags
      param! :tags, Array do |a, i|
        a.param! i, String
      end
      head :ok
    end

    # POST — US2 + feature 013: Array of String items whose `in:` is a
    # qualified constant. The items schema should carry the resolved
    # enum thanks to feature 013's ConstantResolver.
    def moods
      param! :moods, Array, required: false, default: [] do |p, i|
        p.param! i, String, required: true,
                            in: AutoPhotoVhs::EnqueueFurnitureGenerationService::MOODS
      end
      head :ok
    end

    # POST — US3: Three-level deep nesting.
    def nested
      param! :wrapper, Hash do |w|
        w.param! :inner, Hash do |i|
          i.param! :leaf, Integer
        end
      end
      head :ok
    end

    # POST — FR-007: Empty block falls back to a bare object schema.
    def empty_block
      param! :h, Hash do |_q|
        # No nested param! calls.
      end
      head :ok
    end

    # POST — FR-008: Block on a non-Hash/Array type is silently ignored.
    def non_hash_block
      param! :name, String do |s|
        s.param! :ignored, Integer
      end
      head :ok
    end
  end
end
