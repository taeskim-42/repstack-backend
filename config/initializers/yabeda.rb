# frozen_string_literal: true

# Yabeda metrics configuration
# Provides Prometheus-compatible metrics for monitoring

# Only configure if Yabeda is loaded
return unless defined?(Yabeda)

Yabeda.configure do
  # Application info
  gauge :app_info do
    comment "Application version and environment info"
    tags %i[version environment]
  end

  # Custom business metrics
  group :repstack do
    # User metrics
    counter :signups_total do
      comment "Total number of user signups"
      tags %i[status]
    end

    counter :logins_total do
      comment "Total number of login attempts"
      tags %i[status]
    end

    # Workout metrics
    counter :workout_sessions_total do
      comment "Total workout sessions created"
      tags %i[status]
    end

    counter :workout_sets_total do
      comment "Total workout sets logged"
    end

    histogram :workout_session_duration_seconds do
      comment "Duration of workout sessions in seconds"
      unit :seconds
      buckets [ 60, 300, 600, 900, 1800, 3600, 5400, 7200 ]
    end

    # AI routine generation metrics
    counter :routine_generations_total do
      comment "Total AI routine generation requests"
      tags %i[status level mock]
    end

    histogram :routine_generation_duration_seconds do
      comment "Duration of AI routine generation in seconds"
      unit :seconds
      buckets [ 0.1, 0.5, 1, 2, 5, 10, 30, 60 ]
    end

    # Circuit breaker metrics
    gauge :circuit_breaker_state do
      comment "Circuit breaker state (0=closed, 1=open, 2=half-open)"
      tags %i[circuit_name]
    end

    counter :circuit_breaker_trips_total do
      comment "Total number of circuit breaker trips"
      tags %i[circuit_name]
    end

    # Rate limiting metrics
    counter :rate_limit_hits_total do
      comment "Total number of rate limit hits"
      tags %i[throttle_name]
    end
  end

  # Database metrics
  group :database do
    histogram :query_duration_seconds do
      comment "Database query duration in seconds"
      unit :seconds
      buckets [ 0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1 ]
      tags %i[operation]
    end

    gauge :connection_pool_size do
      comment "Database connection pool size"
    end

    gauge :connection_pool_active do
      comment "Active database connections"
    end
  end
end

# Start the Prometheus metrics server if configured
# This exposes metrics on a separate port for Prometheus to scrape
Rails.application.config.after_initialize do
  if ENV["PROMETHEUS_EXPORTER_PORT"].present? && defined?(Yabeda::Prometheus::Exporter)
    begin
      Yabeda::Prometheus::Exporter.start_metrics_server!
      Rails.logger.info("[Yabeda] Prometheus exporter started on port #{ENV['PROMETHEUS_EXPORTER_PORT']}")
    rescue StandardError => e
      Rails.logger.error("[Yabeda] Failed to start Prometheus exporter: #{e.message}")
    end
  end

  # Record app info on startup
  begin
    Yabeda.app_info.set(
      { version: ENV.fetch("APP_VERSION", "unknown"), environment: Rails.env },
      1
    )
  rescue StandardError => e
    Rails.logger.error("[Yabeda] Failed to set app_info: #{e.message}")
  end
end
