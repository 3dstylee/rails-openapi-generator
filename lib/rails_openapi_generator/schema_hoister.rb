# frozen_string_literal: true

module RailsOpenapiGenerator
  # Hoists JSON Schema `$defs` out of inlined schemas (typically schema
  # sidecars) into the document's `components/schemas`, rewriting every
  # `#/$defs/<name>` reference to `#/components/schemas/<key>`.
  #
  # A sidecar's `$ref: "#/$defs/foo"` is document-root-relative: in the
  # standalone schema it resolves against the sidecar's own root, which
  # holds the `$defs`. Once the generator inlines that schema deep inside
  # the OpenAPI document, `#` becomes the OpenAPI root — which has no
  # `$defs` — and tools like Redocly fail with "Invalid reference token:
  # $defs". Hoisting relocates the definitions to a place the rewritten
  # refs can actually reach.
  #
  # Each inlined schema that carries a `$defs` block is treated as one
  # ref-resolution root. Definition names are kept verbatim as component
  # keys; a clash with a differently-shaped definition from another root
  # gets a numeric suffix (`transit_item_2`) so distinct types never
  # collapse into one. Identical definitions reuse the same key.
  class SchemaHoister
    DEFS_REF = %r{\A#/\$defs/(.+)\z}

    def initialize
      @schemas = {}
    end

    # Walks the document, hoisting every `$defs` block found, and attaches
    # a `components/schemas` section when any definitions were collected.
    # Mutates and returns `document`.
    def hoist!(document)
      visit(document)
      unless @schemas.empty?
        components = document["components"] ||= {}
        schemas = components["schemas"] ||= {}
        schemas.merge!(@schemas)
      end
      document
    end

    private

    # Depth-first scan for any Hash carrying a `$defs` key, which marks an
    # inlined-schema ref-resolution root. Roots are processed deepest-first
    # so a nested sidecar's defs are hoisted before its enclosing one.
    def visit(node)
      case node
      when Hash
        node.each_value { |value| visit(value) }
        hoist_root(node) if node.key?("$defs")
      when Array
        node.each { |value| visit(value) }
      end
    end

    def hoist_root(root)
      defs = root.delete("$defs")
      mapping = defs.keys.to_h { |name| [name, allocate_key(name, defs[name])] }

      defs.each { |name, schema| @schemas[mapping[name]] = rewrite_refs(schema, mapping) }
      rewrite_refs(root, mapping)
    end

    # Picks the component key for a definition: its own name when free or
    # already mapped to an identical schema, otherwise the name with the
    # lowest free numeric suffix.
    def allocate_key(name, schema)
      candidate = name
      suffix = 2
      while @schemas.key?(candidate) && @schemas[candidate] != schema
        candidate = "#{name}_#{suffix}"
        suffix += 1
      end
      candidate
    end

    # Rewrites `#/$defs/<name>` refs in place throughout `node` using
    # `mapping` (definition name → component key). Returns `node`.
    def rewrite_refs(node, mapping)
      case node
      when Hash
        ref = node["$ref"]
        if ref.is_a?(String) && (match = DEFS_REF.match(ref)) && mapping.key?(decode(match[1]))
          node["$ref"] = "#/components/schemas/#{mapping[decode(match[1])]}"
        end
        node.each_value { |value| rewrite_refs(value, mapping) }
      when Array
        node.each { |value| rewrite_refs(value, mapping) }
      end
      node
    end

    # Decodes a single JSON Pointer reference token (`~1` → `/`, `~0` → `~`).
    def decode(token)
      token.gsub("~1", "/").gsub("~0", "~")
    end
  end
end
