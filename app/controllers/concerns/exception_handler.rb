# frozen_string_literal: true

module ExceptionHandler
  extend ActiveSupport::Concern

  # Custom exception classes
  class AuthenticationError < StandardError; end
  class UnauthorizedError < StandardError; end
  class MissingToken < StandardError; end
  class InvalidToken < StandardError; end
  class ExpiredSignature < StandardError; end
  class DecodeError < StandardError; end

  included do
    # Order matters: rescue_from statements are processed in reverse order
    rescue_from ExceptionHandler::AuthenticationError, with: :unauthorized_request
    rescue_from ExceptionHandler::UnauthorizedError, with: :unauthorized_request
    rescue_from ExceptionHandler::MissingToken, with: :missing_token
    rescue_from ExceptionHandler::InvalidToken, with: :invalid_token
    rescue_from ExceptionHandler::ExpiredSignature, with: :expired_token
    rescue_from ExceptionHandler::DecodeError, with: :invalid_token
    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity
  end

  private

  # JSON response with message; Status code 422 - unprocessable entity
  def unprocessable_entity(exception)
    render json: {
      message: exception.message
    }, status: :unprocessable_entity
  end

  # JSON response with message; Status code 404 - not found
  def not_found(exception)
    render json: {
      message: exception.message
    }, status: :not_found
  end

  # JSON response with message; Status code 401 - Unauthorized
  def unauthorized_request(exception)
    render json: {
      message: exception.message
    }, status: :unauthorized
  end

  # JSON response with message; Status code 422 - unprocessable entity
  def invalid_token(exception)
    render json: {
      message: exception.message
    }, status: :unprocessable_entity
  end

  # JSON response with message; Status code 422 - unprocessable entity
  def missing_token(exception)
    render json: {
      message: exception.message
    }, status: :unprocessable_entity
  end

  # JSON response with message; Status code 401 - Unauthorized (for expired tokens)
  def expired_token(exception)
    render json: {
      message: exception.message
    }, status: :unauthorized
  end
end