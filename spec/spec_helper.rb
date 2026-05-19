# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require "rails_openapi_generator"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |file| require file }

RSpec.configure do |config|
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.order = :random
  Kernel.srand config.seed

  config.before do
    RailsOpenapiGenerator.reset_configuration!
  end

  # Integration examples tagged :rails_app boot the dummy Rails application once.
  config.before(:each, :rails_app) { DummyApp.boot! }
end
