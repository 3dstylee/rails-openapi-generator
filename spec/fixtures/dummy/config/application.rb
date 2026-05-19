# frozen_string_literal: true

require "rails"
require "action_controller/railtie"

begin
  require "rails_param"
rescue LoadError
  # rails_param is only needed at request time; the generator analyses source statically.
end

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.load_defaults 7.0
    config.eager_load = false
    config.api_only = true
    config.secret_key_base = "dummy-secret-key-base-for-tests"
    config.logger = Logger.new(IO::NULL)
  end
end
