# frozen_string_literal: true

require "optparse"

module RailsOpenapiGenerator
  # A thin command-line wrapper over {Generator}. It parses arguments, boots the
  # host Rails environment, and delegates all generation work to {Generator}.
  class CLI
    # Runs the CLI and returns a process exit code.
    def self.start(argv, stdout: $stdout, stderr: $stderr)
      new(stdout: stdout, stderr: stderr).run(argv)
    end

    def initialize(stdout: $stdout, stderr: $stderr)
      @stdout = stdout
      @stderr = stderr
    end

    def run(argv)
      options = parse(argv)
      return 0 if options[:exit_early]

      boot_rails(options[:rails_root])
      report = Generator.new(build_configuration(options)).generate
      @stdout.puts report.summary
      0
    rescue StandardError => e
      @stderr.puts "Error: #{e.message}"
      1
    end

    private

    def parse(argv)
      options = { rails_root: Dir.pwd }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: rails-openapi-generator [options]"
        opts.on("--rails-root PATH", "Directory of the host Rails app") { |v| options[:rails_root] = v }
        opts.on("--output PATH", "Output document path") { |v| options[:output] = v }
        opts.on("--format FORMAT", %w[json yaml], "Output format (json or yaml)") { |v| options[:format] = v.to_sym }
        opts.on("--version", "Print version and exit") do
          @stdout.puts RailsOpenapiGenerator::VERSION
          options[:exit_early] = true
        end
        opts.on("--help", "Print usage and exit") do
          @stdout.puts opts
          options[:exit_early] = true
        end
      end

      parser.parse(argv)
      options
    end

    def boot_rails(rails_root)
      environment = File.join(File.expand_path(rails_root), "config", "environment.rb")
      unless File.exist?(environment)
        raise ConfigurationError,
              "no Rails app found at #{rails_root} (missing config/environment.rb)"
      end

      require environment
    end

    def build_configuration(options)
      configuration = RailsOpenapiGenerator.configuration
      configuration.output_path = options[:output] if options[:output]
      configuration.format      = options[:format] if options[:format]
      configuration
    end
  end
end
