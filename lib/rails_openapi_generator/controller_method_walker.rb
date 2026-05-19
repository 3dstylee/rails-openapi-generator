# frozen_string_literal: true

require "set"

module RailsOpenapiGenerator
  # Walks a controller action together with the receiverless helper methods it
  # calls — recursively, bounded by a maximum depth and guarded against cycles —
  # and returns every reachable method body. Shared by features that inspect an
  # action and its helpers (wrapper-download resolution, implicit-params scan).
  class ControllerMethodWalker
    def initialize(method_resolver:, max_depth: 5)
      @method_resolver = method_resolver
      @max_depth = max_depth
    end

    # Returns the action body plus every resolved receiverless helper body.
    def reachable_bodies(controller_class, action_node)
      return [] if action_node.nil?

      bodies = []
      collect(controller_class, action_node, 0, Set.new, bodies)
      bodies
    end

    # Names of every method call made with no explicit receiver in the subtree:
    # `:command` (`foo bar`), `:vcall` (`foo`), and `:fcall` (`foo(bar)`).
    def self.receiverless_call_names(node, names = [])
      return names unless node.is_a?(Array)

      if %i[command vcall fcall].include?(node[0])
        ident = node[1]
        names << ident[1] if ident.is_a?(Array) && ident[0] == :@ident
      end

      node.each { |child| receiverless_call_names(child, names) if child.is_a?(Array) }
      names
    end

    private

    def collect(controller_class, node, depth, visited, bodies)
      bodies << node
      return if depth >= @max_depth || controller_class.nil?

      self.class.receiverless_call_names(node).uniq.each do |name|
        resolved = @method_resolver.resolve(controller_class, name)
        next if resolved.nil? || visited.include?(resolved.location)

        visited.add(resolved.location)
        collect(controller_class, resolved.node, depth + 1, visited, bodies)
      end
    end
  end
end
