# frozen_string_literal: true

require "yard"
require "ripper"
require "stringio"

module RailsOpenapiGenerator
  # The static-analysis result for a single controller action method.
  ActionSource = Struct.new(:name, :docstring, :method_node, :line, keyword_init: true)

  # Parses a controller source file once, exposing each action's YARD docstring
  # and Ripper AST. No controller code is executed.
  class YardParser
    def initialize
      @cache = {}
      silence_yard
    end

    # Returns a Hash of action name => {ActionSource} for the given file.
    # Results are cached so each file is parsed at most once.
    def parse(file_path)
      @cache[file_path] ||= parse_file(file_path)
    end

    private

    def parse_file(file_path)
      source     = File.read(file_path)
      docstrings = extract_docstrings(file_path)
      sexp       = Ripper.sexp(source)

      raise Error, "could not parse Ruby source: #{file_path}" if sexp.nil?

      extract_method_nodes(sexp).transform_values do |node|
        name = method_name(node)
        ActionSource.new(name: name, docstring: docstrings[name], method_node: node, line: method_line(node))
      end
    end

    # Builds a name => YARD docstring text map using YARD's global registry.
    def extract_docstrings(file_path)
      YARD::Registry.clear
      YARD.parse(file_path, [])
      YARD::Registry.all(:method).each_with_object({}) do |object, result|
        text = object.docstring.to_s
        result[object.name.to_s] = text unless text.strip.empty?
      end
    ensure
      YARD::Registry.clear
    end

    # Collects every `def` node in the file, keyed by method name.
    def extract_method_nodes(sexp, result = {})
      return result unless sexp.is_a?(Array)

      if sexp[0] == :def && (name = method_name(sexp))
        result[name] = sexp
      end

      sexp.each { |child| extract_method_nodes(child, result) if child.is_a?(Array) }
      result
    end

    def method_name(def_node)
      ident = def_node[1]
      ident.is_a?(Array) && ident[0] == :@ident ? ident[1] : nil
    end

    # The 1-based source line of a `def` node, read from its Ripper position.
    def method_line(def_node)
      ident = def_node[1]
      ident.is_a?(Array) && ident[2].is_a?(Array) ? ident[2][0] : nil
    end

    def silence_yard
      YARD::Logger.instance.io = StringIO.new
    rescue StandardError
      # If YARD's logger API changes, parsing still works — only logging is affected.
    end
  end
end
