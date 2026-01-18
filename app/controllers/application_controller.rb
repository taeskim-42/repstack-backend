# frozen_string_literal: true

class ApplicationController < ActionController::API
  include ExceptionHandler

  # called before every action on controllers
  before_action :authorize_request

  attr_reader :current_user

  private

  # Check for valid request token and return user
  def authorize_request
    @current_user = (AuthorizeApiRequest.new(request.headers).call)[:user]
  rescue ExceptionHandler::MissingToken, ExceptionHandler::InvalidToken => e
    # For GraphQL endpoint, we want to allow requests without authentication
    # The GraphQL resolvers can handle authentication requirements individually
    @current_user = nil
    raise e unless skip_authentication?
  end

  def authenticate_user!
    raise ExceptionHandler::AuthenticationError, 'Unauthorized request' unless current_user
  end

  # Override this method in controllers that should allow unauthenticated access
  def skip_authentication?
    false
  end
end