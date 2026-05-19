# frozen_string_literal: true

module Api
  class PostsController < ApplicationController
    # List posts
    def index
      render json: []
    end
  end
end
