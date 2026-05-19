# frozen_string_literal: true

module RailsOpenapiGenerator
  # Determines whether a controller action performs a file download — directly
  # or through one or more wrapper methods. The action and its receiverless
  # helper methods are walked recursively by a {ControllerMethodWalker}; the
  # action is a download when any reachable body calls `send_file`/`send_data`.
  class WrapperDownloadResolver
    DOWNLOAD_METHODS = %w[send_file send_data].freeze

    def initialize(walker:)
      @walker = walker
    end

    # Returns true if the action — or a wrapper it reaches — performs a download.
    def download?(controller_class, action_node)
      return false if controller_class.nil? || action_node.nil?

      @walker.reachable_bodies(controller_class, action_node).any? do |body|
        ControllerMethodWalker.receiverless_call_names(body).any? do |name|
          DOWNLOAD_METHODS.include?(name)
        end
      end
    end
  end
end
