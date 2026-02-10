# frozen_string_literal: true

# Base controller for Internal API (Agent Service → Rails)
# Protected by Bearer token authentication (RAILS_API_TOKEN)
module Internal
  class BaseController < ActionController::API
    before_action :authenticate_internal_api!
    before_action :set_user

    private

    def authenticate_internal_api!
      token = request.headers["Authorization"]&.split("Bearer ")&.last
      expected = ENV["RAILS_API_TOKEN"]

      if expected.blank?
        render json: { error: "Internal API not configured" }, status: :service_unavailable
        return
      end

      unless ActiveSupport::SecurityUtils.secure_compare(token.to_s, expected)
        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end

    def set_user
      @user = User.find_by(id: params[:user_id])
      render json: { error: "User not found" }, status: :not_found unless @user
    end

    def render_success(data = {})
      render json: { success: true }.merge(data)
    end

    def render_error(message, status: :unprocessable_entity)
      render json: { success: false, error: message }, status: status
    end
  end
end
