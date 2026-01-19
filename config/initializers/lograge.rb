# frozen_string_literal: true

# Lograge configuration for structured logging
# Converts Rails request logs into single-line JSON format for easier parsing

Rails.application.configure do
  config.lograge.enabled = true

  # Use JSON formatter for structured logging
  config.lograge.formatter = Lograge::Formatters::Json.new

  # Keep original Rails logger for non-request logs
  config.lograge.keep_original_rails_log = false

  # Custom options to include in each log entry
  config.lograge.custom_options = lambda do |event|
    options = {
      # Request identification
      request_id: event.payload[:request_id],
      correlation_id: event.payload[:correlation_id],

      # Timing breakdown
      time: Time.current.iso8601,
      timestamp_ms: (Time.current.to_f * 1000).to_i,

      # Request details
      host: event.payload[:host],
      remote_ip: event.payload[:remote_ip],
      user_agent: event.payload[:user_agent],

      # User context (if authenticated)
      user_id: event.payload[:user_id],

      # Application context
      environment: Rails.env,
      service: "repstack-backend",
      version: ENV.fetch("APP_VERSION", "unknown")
    }

    # Add exception details if present
    if event.payload[:exception]
      exception_class, exception_message = event.payload[:exception]
      options[:exception] = {
        class: exception_class,
        message: exception_message
      }
      options[:exception_backtrace] = event.payload[:exception_object]&.backtrace&.first(5)
    end

    # Add GraphQL-specific data if present
    if event.payload[:graphql_operation]
      options[:graphql] = {
        operation_name: event.payload[:graphql_operation],
        operation_type: event.payload[:graphql_operation_type],
        variables: event.payload[:graphql_variables]
      }
    end

    options.compact
  end

  # Custom payload additions in controller
  config.lograge.custom_payload do |controller|
    user_id = controller.try(:current_user)&.id

    {
      host: controller.request.host,
      remote_ip: controller.request.remote_ip,
      user_agent: controller.request.user_agent,
      user_id: user_id,
      request_id: controller.request.request_id,
      correlation_id: controller.request.headers["X-Correlation-ID"]
    }
  end

  # Ignore health check endpoints in logs (reduce noise)
  config.lograge.ignore_actions = [
    "HealthController#show",
    "HealthController#ready"
  ]

  # Log level based on environment
  config.log_level = Rails.env.production? ? :info : :debug
end
