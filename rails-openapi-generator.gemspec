# frozen_string_literal: true

require_relative "lib/rails_openapi_generator/version"

Gem::Specification.new do |spec|
  spec.name        = "rails-openapi-generator"
  spec.version     = RailsOpenapiGenerator::VERSION
  spec.authors     = ["Tony Duong"]
  spec.summary     = "Generate OpenAPI documents from Rails routes, rails_param validations, and YARD comments"
  spec.description = "A Ruby gem that generates a single OpenAPI 3.1 document for a Rails application. " \
                     "Endpoints are discovered from the route set, request parameters are derived from " \
                     "rails_param declarations, and operation summaries/descriptions are taken from YARD comments."
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.1"
  spec.metadata = { "rubygems_mfa_required" => "true" }

  spec.files = Dir["lib/**/*", "exe/*", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["rails-openapi-generator"]
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 7.0"
  spec.add_dependency "yard", "~> 0.9"

  spec.add_development_dependency "json_schemer", "~> 2.0"
  spec.add_development_dependency "rails", ">= 7.0"
  spec.add_development_dependency "rails_param", ">= 1.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
end
