# frozen_string_literal: true

# Legacy exception handler for models
# This module is kept for backwards compatibility
# The primary exception handling is now in app/controllers/concerns/exception_handler.rb
#
# @deprecated Use the controller concern instead for new code
module ExceptionHandler
  extend ActiveSupport::Concern

  # Re-export exception classes from the controller concern for compatibility
  # These are the canonical exception classes used throughout the application
  AuthenticationError = Class.new(StandardError)
  MissingToken = Class.new(StandardError)
  InvalidToken = Class.new(StandardError)
  ExpiredSignature = Class.new(StandardError)
  DecodeError = Class.new(StandardError)

  included do
    rescue_from ActiveRecord::RecordInvalid, with: :handle_validation_error
    rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
    rescue_from ExceptionHandler::AuthenticationError, with: :handle_unauthorized
    rescue_from ExceptionHandler::MissingToken, with: :handle_validation_error
    rescue_from ExceptionHandler::InvalidToken, with: :handle_validation_error
    rescue_from ExceptionHandler::ExpiredSignature, with: :handle_token_expired
    rescue_from ExceptionHandler::DecodeError, with: :handle_unauthorized
  end

  private

  def json_response(object, status = :ok)
    render json: object, status: status
  end

  def handle_validation_error(exception)
    message = exception.respond_to?(:record) ? exception.record.errors.full_messages.join(", ") : exception.message
    json_response({ error: true, message: message }, :unprocessable_entity)
  end

  def handle_not_found(exception)
    json_response({ error: true, message: exception.message }, :not_found)
  end

  def handle_unauthorized(exception)
    json_response({ error: true, message: exception.message }, :unauthorized)
  end

  def handle_token_expired(exception)
    json_response({ error: true, message: "Token has expired" }, :unauthorized)
  end
end