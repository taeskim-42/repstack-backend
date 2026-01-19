# frozen_string_literal: true

# Health check controller for monitoring and orchestration
# Provides endpoints for liveness and readiness probes
class HealthController < ActionController::API
  # Skip all authentication and rate limiting for health checks
  skip_before_action :authorize_request, raise: false

  # GET /health
  # Basic liveness probe - returns 200 if the app is running
  def show
    render json: {
      status: "ok",
      timestamp: Time.current.iso8601,
      service: "repstack-backend",
      version: app_version
    }, status: :ok
  end

  # GET /health/ready
  # Readiness probe - checks if the app can serve traffic
  def ready
    checks = perform_readiness_checks
    all_healthy = checks.values.all? { |check| check[:healthy] }

    status_code = all_healthy ? :ok : :service_unavailable

    render json: {
      status: all_healthy ? "ready" : "not_ready",
      timestamp: Time.current.iso8601,
      checks: checks
    }, status: status_code
  end

  # GET /health/live
  # Liveness probe - indicates if the app should be restarted
  def live
    render json: {
      status: "alive",
      timestamp: Time.current.iso8601,
      uptime_seconds: uptime_seconds
    }, status: :ok
  end

  # GET /health/details
  # Detailed health check with all system information (protected endpoint)
  def details
    checks = perform_all_checks

    render json: {
      status: overall_status(checks),
      timestamp: Time.current.iso8601,
      service: "repstack-backend",
      version: app_version,
      environment: Rails.env,
      ruby_version: RUBY_VERSION,
      rails_version: Rails::VERSION::STRING,
      uptime_seconds: uptime_seconds,
      checks: checks
    }, status: :ok
  end

  private

  def perform_readiness_checks
    {
      database: check_database,
      cache: check_cache
    }
  end

  def perform_all_checks
    {
      database: check_database,
      cache: check_cache,
      claude_api: check_claude_api,
      memory: check_memory,
      disk: check_disk
    }
  end

  def check_database
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ActiveRecord::Base.connection.execute("SELECT 1")
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

    {
      healthy: true,
      latency_ms: duration_ms,
      pool_size: ActiveRecord::Base.connection_pool.size,
      connections_in_use: ActiveRecord::Base.connection_pool.connections.count(&:in_use?)
    }
  rescue StandardError => e
    {
      healthy: false,
      error: e.message
    }
  end

  def check_cache
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    test_key = "health_check_#{SecureRandom.hex(4)}"

    Rails.cache.write(test_key, "ok", expires_in: 10.seconds)
    result = Rails.cache.read(test_key)
    Rails.cache.delete(test_key)

    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

    {
      healthy: result == "ok",
      latency_ms: duration_ms,
      store: Rails.cache.class.name
    }
  rescue StandardError => e
    {
      healthy: false,
      error: e.message
    }
  end

  def check_claude_api
    circuit_stats = ClaudeApiService.circuit_stats

    {
      healthy: !circuit_stats[:open],
      circuit_open: circuit_stats[:open],
      error_rate: circuit_stats[:error_rate],
      api_configured: ENV["ANTHROPIC_API_KEY"].present?
    }
  rescue StandardError => e
    {
      healthy: false,
      error: e.message
    }
  end

  def check_memory
    # Memory usage in MB
    memory_mb = `ps -o rss= -p #{Process.pid}`.to_i / 1024.0

    {
      healthy: memory_mb < 512, # Threshold: 512MB
      usage_mb: memory_mb.round(2),
      threshold_mb: 512
    }
  rescue StandardError => e
    {
      healthy: true, # Don't fail health check if memory check fails
      error: e.message
    }
  end

  def check_disk
    # Check available disk space (on root partition)
    stat = Sys::Filesystem.stat("/") if defined?(Sys::Filesystem)

    if stat
      available_gb = stat.bytes_available / (1024.0**3)
      total_gb = stat.bytes_total / (1024.0**3)
      usage_percent = ((total_gb - available_gb) / total_gb * 100).round(1)

      {
        healthy: available_gb > 1, # Threshold: 1GB
        available_gb: available_gb.round(2),
        usage_percent: usage_percent
      }
    else
      { healthy: true, message: "Disk check not available" }
    end
  rescue StandardError => e
    {
      healthy: true, # Don't fail health check if disk check fails
      error: e.message
    }
  end

  def overall_status(checks)
    critical_checks = [:database, :cache]
    critical_healthy = critical_checks.all? { |check| checks[check][:healthy] }

    if critical_healthy
      checks.values.all? { |c| c[:healthy] } ? "healthy" : "degraded"
    else
      "unhealthy"
    end
  end

  def app_version
    ENV.fetch("APP_VERSION") { git_sha || "unknown" }
  end

  def git_sha
    @git_sha ||= begin
      `git rev-parse --short HEAD 2>/dev/null`.strip.presence
    rescue StandardError
      nil
    end
  end

  def uptime_seconds
    @boot_time ||= Time.current
    (Time.current - @boot_time).to_i
  end

  class << self
    attr_accessor :boot_time
  end
end

# Record boot time
HealthController.boot_time = Time.current
