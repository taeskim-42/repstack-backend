# frozen_string_literal: true

class GraphqlController < ApplicationController
  # Skip authentication requirement for GraphQL endpoint
  # Individual resolvers can enforce authentication as needed
  skip_before_action :authorize_request
  before_action :set_current_user
  before_action :set_request_id

  # If accessing from outside this domain, nullify the session
  # This allows for outside API access while preventing CSRF attacks,
  # but you'll have to authenticate your user separately
  # protect_from_forgery with: :null_session

  def execute
    variables = prepare_variables(params[:variables])
    query = params[:query]
    operation_name = params[:operationName]

    # Extract operation info for logging
    append_info_to_payload_for_logging(operation_name, variables)

    context = {
      current_user: current_user,
      request: request,
      request_id: @request_id
    }

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = RepstackBackendSchema.execute(query, variables: variables, context: context, operation_name: operation_name)
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

    log_graphql_execution(operation_name, duration_ms, result)

    render json: result
  rescue StandardError => e
    log_graphql_error(e)
    raise e unless Rails.env.development?
    handle_error_in_development(e)
  end

  private

  # Set current_user without raising exceptions
  def set_current_user
    @current_user = (AuthorizeApiRequest.new(request.headers).call)[:user]
  rescue ExceptionHandler::MissingToken, ExceptionHandler::InvalidToken
    # Silently set current_user to nil if no valid token
    @current_user = nil
  end

  def skip_authentication?
    true
  end

  # Handle variables in form data, JSON body, or a blank value
  def prepare_variables(variables_param)
    case variables_param
    when String
      if variables_param.present?
        JSON.parse(variables_param) || {}
      else
        {}
      end
    when Hash
      variables_param
    when ActionController::Parameters
      variables_param.to_unsafe_hash # GraphQL-Ruby will validate name and type of incoming variables.
    when nil
      {}
    else
      raise ArgumentError, "Unexpected parameter: #{variables_param}"
    end
  end

  def handle_error_in_development(e)
    logger.error e.message
    logger.error e.backtrace.join("\n")

    render json: { errors: [{ message: e.message, backtrace: e.backtrace }], data: {} }, status: 500
  end

  def set_request_id
    @request_id = request.headers["X-Request-ID"] || request.request_id || SecureRandom.uuid
    response.headers["X-Request-ID"] = @request_id
  end

  def append_info_to_payload_for_logging(operation_name, variables)
    # Add GraphQL info to Lograge payload
    request.env["action_dispatch.request.parameters"][:graphql_operation] = operation_name
    request.env["action_dispatch.request.parameters"][:graphql_operation_type] = detect_operation_type(params[:query])

    # Sanitize variables for logging (remove sensitive data)
    request.env["action_dispatch.request.parameters"][:graphql_variables] = sanitize_variables_for_logging(variables)
  end

  def detect_operation_type(query)
    return "unknown" if query.blank?

    if query.strip.start_with?("mutation")
      "mutation"
    elsif query.strip.start_with?("subscription")
      "subscription"
    else
      "query"
    end
  end

  def sanitize_variables_for_logging(variables)
    return {} if variables.blank?

    sensitive_keys = %w[password passwordConfirmation token apiKey secret]
    variables.transform_values.with_index do |(key, value), _|
      if sensitive_keys.any? { |sk| key.to_s.downcase.include?(sk.downcase) }
        "[FILTERED]"
      else
        value
      end
    end
  rescue StandardError
    {}
  end

  def log_graphql_execution(operation_name, duration_ms, result)
    errors = result["errors"]

    log_data = {
      event: "graphql.execute",
      request_id: @request_id,
      operation: operation_name || "anonymous",
      duration_ms: duration_ms,
      user_id: current_user&.id,
      has_errors: errors.present?,
      error_count: errors&.length || 0
    }

    if errors.present?
      Rails.logger.warn(log_data.merge(errors: errors.map { |e| e["message"] }).to_json)
    else
      Rails.logger.info(log_data.to_json)
    end
  end

  def log_graphql_error(exception)
    Rails.logger.error({
      event: "graphql.error",
      request_id: @request_id,
      error_class: exception.class.name,
      error_message: exception.message,
      backtrace: exception.backtrace&.first(5)
    }.to_json)
  end
end