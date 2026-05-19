# frozen_string_literal: true

require "set"

module RailsOpenapiGenerator
  # Determines whether a controller action performs a file download through one
  # or more wrapper methods. When the action does not call `send_file`/`send_data`
  # directly, its receiverless calls are followed to their definitions and
  # inspected in turn — recursively, bounded by a maximum depth, and guarded
  # against cycles.
  class WrapperDownloadResolver
    DOWNLOAD_METHODS = %w[send_file send_data].freeze

    def initialize(method_resolver:, max_depth: 5)
      @method_resolver = method_resolver
      @max_depth = max_depth
    end

    # Returns true if the action — or a wrapper it reaches — performs a download.
    def download?(controller_class, action_node)
      return false if controller_class.nil? || action_node.nil?

      download_from?(controller_class, action_node, 0, Set.new)
    end

    private

    def download_from?(controller_class, node, depth, visited)
      call_names = receiverless_call_names(node)
      return true if call_names.any? { |name| DOWNLOAD_METHODS.include?(name) }
      return false if depth >= @max_depth

      call_names.each do |name|
        next if DOWNLOAD_METHODS.include?(name)

        resolved = @method_resolver.resolve(controller_class, name)
        next if resolved.nil? || visited.include?(resolved.location)

        visited.add(resolved.location)
        return true if download_from?(controller_class, resolved.node, depth + 1, visited)
      end
      false
    end

    # Names of every method call made with no explicit receiver in the subtree:
    # `:command` (`foo bar`), `:vcall` (`foo`), and `:fcall` (`foo(bar)`).
    # Explicit-receiver calls (`:call` / `:command_call`) are not collected.
    def receiverless_call_names(node, names = [])
      return names unless node.is_a?(Array)

      if %i[command vcall fcall].include?(node[0])
        ident = node[1]
        names << ident[1] if ident.is_a?(Array) && ident[0] == :@ident
      end

      node.each { |child| receiverless_call_names(child, names) if child.is_a?(Array) }
      names
    end
  end
end
