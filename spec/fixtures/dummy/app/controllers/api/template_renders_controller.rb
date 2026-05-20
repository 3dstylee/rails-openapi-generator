# frozen_string_literal: true

module Api
  class TemplateRendersController < ApplicationController
    before_action :forbid_unless_admin, only: [:destroy]

    # PUT — the motivating shape: a guard error render in the action body,
    # and a happy template render inside a private helper. The doc should
    # show 200 (from the helper) and 409 (from the action body).
    def update
      return render_error unless params[:ok]

      render_show
    end

    # GET — explicit `formats: :html` inside a helper. The doc should show
    # the operation as an HTML page (single entry, text/html content).
    def as_html
      render_html_show
    end

    # GET — template render whose target view does not exist. The doc
    # should show one entry under the convention status with no content.
    def missing
      render_missing
    end

    # DELETE — head :no_content for the happy path; the before_action
    # contributes a 403 template render at status :forbidden.
    def destroy
      head :no_content
    end

    private

    def render_show
      render "api/template_renders/show", formats: :json, handlers: [:jbuilder]
    end

    def render_html_show
      render "api/template_renders/show", formats: :html
    end

    def render_missing
      render "api/template_renders/no_such_view"
    end

    def render_error
      render json: { message: "conflict" }, status: :conflict
    end

    def forbid_unless_admin
      return if defined?(current_user_admin?) && current_user_admin?

      render "api/template_renders/forbidden", status: :forbidden, formats: :json
    end
  end
end
