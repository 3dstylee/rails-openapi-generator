# frozen_string_literal: true

module Api
  class RespondToController < ApplicationController
    # GET — the motivating shape: format.html with a body block, plus a
    # bare format.json. The operation should document 200 with both
    # application/json (jbuilder schema) and text/html content types.
    def index
      respond_to do |format|
        format.html do
          @gon_payload = params[:payload]
        end
        format.json
      end
    end

    # GET — single content type (JSON only). The operation should document
    # 200 with only the application/json content (no text/html entry).
    def json_only
      respond_to do |format|
        format.json
      end
    end

    # GET — single content type (HTML only). The operation should
    # document as :html_page (text/html, x-renders-html), byte-identical
    # to today's HTML-page shape.
    def html_only
      respond_to do |format|
        format.html
      end
    end

    # GET — inline `render json:` inside the format.json block overrides
    # the default-view lookup; the format.html block falls back to the
    # default `.html.erb`.
    def explicit_json
      respond_to do |format|
        format.json { render json: { id: 1, ok: true } }
        format.html
      end
    end

    # GET — `format.xml` is unmapped in v1; the gate is silently ignored
    # and the operation falls back to today's classification rules.
    def unmapped
      respond_to do |format|
        format.xml
      end
    end
  end
end
