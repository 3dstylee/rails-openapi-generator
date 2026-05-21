# frozen_string_literal: true

module AutoPhotoVhs
  class EnqueueFurnitureGenerationService
    # Array of literal Strings → schema-compatible (enum).
    MOODS = %w[modern classic minimalist scandinavian industrial].freeze

    # Range of Integers → schema-compatible (minimum / maximum).
    PAGE_RANGE = (1..100)

    # Regexp → schema-compatible (pattern).
    EMAIL_PATTERN = /\A[^@\s]+@[^@\s]+\z/

    # A class — NOT schema-compatible; should resolve to UNRESOLVED.
    CLASS_REF = String

    def self.execute(*)
      :noop
    end
  end
end
