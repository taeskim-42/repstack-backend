# frozen_string_literal: true

# Unified exception handling for Rails controllers
# This module provides consistent error responses across all API endpoints
module ExceptionHandler
  extend ActiveSupport::Concern

  # Custom exception classes for authentication and authorization
  class AuthenticationError < StandardError; end
  class UnauthorizedError < StandardError; end
  class MissingToken < StandardError; end
  class InvalidToken < StandardError; end
  class ExpiredSignature < StandardError; end
  class DecodeError < StandardError; end

  # HTTP status codes for reference
  HTTP_STATUS = {
    ok: 200,
    bad_request: 400,
    unauthorized: 401,
    forbidden: 403,
    not_found: 404,
    unprocessable_entity: 422,
    internal_server_error: 500
  }.freeze

  included do
    # Order matters: rescue_from statements are processed in reverse order (LIFO)
    # More specific exceptions should be listed last
    rescue_from StandardError, with: :internal_error if Rails.env.production?
    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity
    rescue_from ActionController::ParameterMissing, with: :bad_request

    # Authentication-related exceptions
    rescue_from ExceptionHandler::AuthenticationError, with: :unauthorized_request
    rescue_from ExceptionHandler::UnauthorizedError, with: :unauthorized_request
    rescue_from ExceptionHandler::MissingToken, with: :missing_token
    rescue_from ExceptionHandler::InvalidToken, with: :invalid_token
    rescue_from ExceptionHandler::ExpiredSignature, with: :expired_token
    rescue_from ExceptionHandler::DecodeError, with: :invalid_token
  end

  private

  # Generic JSON response helper
  def json_response(object, status = :ok)
    render json: object, status: status
  end

  # JSON error response with consistent format
  def error_response(message, status)
    json_response({ error: true, message: message }, status)
  end

  # Status code 400 - Bad Request
  def bad_request(exception)
    log_exception(exception, :warn)
    error_response(exception.message, :bad_request)
  end

  # Status code 401 - Unauthorized
  def unauthorized_request(exception)
    log_exception(exception, :warn)
    error_response(exception.message, :unauthorized)
  end

  # Status code 401 - Unauthorized (for expired tokens)
  def expired_token(exception)
    log_exception(exception, :warn)
    error_response("Token has expired. Please sign in again.", :unauthorized)
  end

  # Status code 404 - Not Found
  def not_found(exception)
    log_exception(exception, :info)
    error_response(exception.message, :not_found)
  end

  # Status code 422 - Unprocessable Entity
  def unprocessable_entity(exception)
    log_exception(exception, :warn)
    message = exception.respond_to?(:record) ? exception.record.errors.full_messages.join(", ") : exception.message
    error_response(message, :unprocessable_entity)
  end

  # Status code 422 - Unprocessable Entity (for invalid tokens)
  def invalid_token(exception)
    log_exception(exception, :warn)
    error_response("Invalid token. Please sign in again.", :unprocessable_entity)
  end

  # Status code 422 - Unprocessable Entity (for missing tokens)
  def missing_token(exception)
    log_exception(exception, :warn)
    error_response("Authentication token is missing.", :unprocessable_entity)
  end

  # Status code 500 - Internal Server Error (production only)
  def internal_error(exception)
    log_exception(exception, :error)
    error_response("An unexpected error occurred. Please try again later.", :internal_server_error)
  end

  # Centralized exception logging
  def log_exception(exception, level = :error)
    message = "[#{exception.class}] #{exception.message}"
    case level
    when :info
      Rails.logger.info(message)
    when :warn
      Rails.logger.warn(message)
    else
      Rails.logger.error(message)
      Rails.logger.error(exception.backtrace&.first(10)&.join("\n")) if Rails.env.development?
    end
  end
end