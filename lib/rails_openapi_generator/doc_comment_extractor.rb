# frozen_string_literal: true

module RailsOpenapiGenerator
  # Human-readable text extracted from a YARD docstring.
  DocComment = Struct.new(:summary, :description, keyword_init: true)

  # Extracts an operation summary and description from an action's YARD docstring.
  class DocCommentExtractor
    EMPTY = DocComment.new(summary: nil, description: nil).freeze

    # Returns a {DocComment} for the given {ActionSource}; fields are nil when absent.
    def extract(action_source)
      return EMPTY if action_source.nil?

      text = action_source.docstring
      return EMPTY if text.nil? || text.strip.empty?

      lines       = text.strip.split("\n")
      summary     = lines.first&.strip
      description = lines[1..]&.join("\n")&.strip
      description = nil if description.nil? || description.empty?

      DocComment.new(summary: summary, description: description)
    end
  end
end
