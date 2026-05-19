# frozen_string_literal: true

# Boots the dummy Rails application fixture exactly once per test process.
module DummyApp
  ROOT = File.expand_path("../fixtures/dummy", __dir__)

  class << self
    def boot!
      return if @booted

      require File.join(ROOT, "config", "environment")
      @booted = true
    end

    def booted?
      @booted == true
    end
  end
end
