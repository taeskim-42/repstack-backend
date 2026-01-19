# frozen_string_literal: true

# OpenTelemetry configuration for distributed tracing
# Enables request tracing across services

# Only load if OpenTelemetry gems are available
begin
  require "opentelemetry/sdk"
  require "opentelemetry/exporter/otlp"
  require "opentelemetry/instrumentation/all"
rescue LoadError => e
  Rails.logger.info "[OpenTelemetry] Gems not available, skipping configuration: #{e.message}"
  return
end

# Only enable in production or when explicitly configured
if ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].present? || Rails.env.production?
  begin
    OpenTelemetry::SDK.configure do |c|
      # Service identification
      c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "repstack-backend")
      c.service_version = ENV.fetch("APP_VERSION", "unknown")

      # Configure resource attributes
      c.resource = OpenTelemetry::SDK::Resources::Resource.create(
        OpenTelemetry::SemanticConventions::Resource::SERVICE_NAME => "repstack-backend",
        OpenTelemetry::SemanticConventions::Resource::SERVICE_VERSION => ENV.fetch("APP_VERSION", "unknown"),
        OpenTelemetry::SemanticConventions::Resource::DEPLOYMENT_ENVIRONMENT => Rails.env,
        "service.instance.id" => Socket.gethostname
      )

      # Auto-instrument all supported libraries
      c.use_all

      # Batch span processor for better performance
      c.add_span_processor(
        OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
          OpenTelemetry::Exporter::OTLP::Exporter.new(
            endpoint: ENV.fetch("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318/v1/traces"),
            headers: parse_otel_headers
          )
        )
      )
    end

    Rails.logger.info "[OpenTelemetry] Tracing enabled for repstack-backend"
  rescue StandardError => e
    Rails.logger.error "[OpenTelemetry] Failed to configure: #{e.message}"
  end
else
  Rails.logger.info "[OpenTelemetry] Tracing disabled (set OTEL_EXPORTER_OTLP_ENDPOINT to enable)"
end

# Parse OTEL headers from environment variable
def parse_otel_headers
  headers_str = ENV.fetch("OTEL_EXPORTER_OTLP_HEADERS", "")
  return {} if headers_str.blank?

  headers_str.split(",").each_with_object({}) do |header, hash|
    key, value = header.split("=", 2)
    hash[key.strip] = value&.strip if key.present?
  end
end

# Custom span helper for application code
module Tracing
  class << self
    def tracer
      return nil unless tracing_available?

      OpenTelemetry.tracer_provider.tracer("repstack-backend")
    end

    # Wrap a block in a custom span
    def with_span(name, attributes: {}, kind: :internal)
      return yield unless tracing_enabled?

      tracer.in_span(name, attributes: attributes, kind: kind) do |span|
        yield span
      end
    rescue StandardError => e
      Rails.logger.debug "[Tracing] with_span failed: #{e.message}"
      yield nil
    end

    # Add attributes to the current span
    def set_attributes(attributes)
      return unless tracing_enabled?

      span = OpenTelemetry::Trace.current_span
      attributes.each { |k, v| span.set_attribute(k.to_s, v) }
    rescue StandardError => e
      Rails.logger.debug "[Tracing] set_attributes failed: #{e.message}"
    end

    # Record an exception on the current span
    def record_exception(exception)
      return unless tracing_enabled?

      span = OpenTelemetry::Trace.current_span
      span.record_exception(exception)
      span.status = OpenTelemetry::Trace::Status.error(exception.message)
    rescue StandardError => e
      Rails.logger.debug "[Tracing] record_exception failed: #{e.message}"
    end

    # Get the current trace ID for logging correlation
    def current_trace_id
      return nil unless tracing_enabled?

      span = OpenTelemetry::Trace.current_span
      span.context.trace_id.unpack1("H*")
    rescue StandardError
      nil
    end

    private

    def tracing_available?
      defined?(OpenTelemetry) && defined?(OpenTelemetry::Trace)
    end

    def tracing_enabled?
      tracing_available? && (ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].present? || Rails.env.production?)
    end
  end
end
