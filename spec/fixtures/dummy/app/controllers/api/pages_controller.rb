# frozen_string_literal: true

module Api
  class PagesController < ApplicationController
    # Show a page
    #
    # Renders an HTML view implicitly (no `render` line) — an HTML-page endpoint.
    def show; end

    # Download a file — a file-download endpoint.
    def download
      send_file Rails.root.join("README"), filename: "page.txt"
    end
  end
end
