# frozen_string_literal: true

module RailsOpenapiGenerator
  # Registers the gem's rake task with the host Rails application.
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("../tasks/rails_openapi_generator.rake", __dir__)
    end
  end
end
