# frozen_string_literal: true

# Centralized metrics collection service
# Provides a clean interface for recording application metrics
# Safely handles cases where Yabeda isn't loaded or configured
class MetricsService
  class << self
    # User metrics
    def record_signup(success:)
      return unless metrics_enabled?

      Yabeda.repstack.signups_total.increment({ status: success ? "success" : "failure" })
    rescue StandardError => e
      log_metrics_error("record_signup", e)
    end

    def record_login(success:)
      return unless metrics_enabled?

      Yabeda.repstack.logins_total.increment({ status: success ? "success" : "failure" })
    rescue StandardError => e
      log_metrics_error("record_login", e)
    end

    # Workout metrics
    def record_workout_session_created(success:)
      return unless metrics_enabled?

      Yabeda.repstack.workout_sessions_total.increment({ status: success ? "success" : "failure" })
    rescue StandardError => e
      log_metrics_error("record_workout_session_created", e)
    end

    def record_workout_set_logged
      return unless metrics_enabled?

      Yabeda.repstack.workout_sets_total.increment({})
    rescue StandardError => e
      log_metrics_error("record_workout_set_logged", e)
    end

    def record_workout_session_duration(duration_seconds)
      return unless metrics_enabled?

      Yabeda.repstack.workout_session_duration_seconds.measure({}, duration_seconds)
    rescue StandardError => e
      log_metrics_error("record_workout_session_duration", e)
    end

    # AI routine generation metrics
    def record_routine_generation(success:, level:, mock:, duration_seconds:)
      return unless metrics_enabled?

      Yabeda.repstack.routine_generations_total.increment({
        status: success ? "success" : "failure",
        level: level.to_s,
        mock: mock.to_s
      })

      Yabeda.repstack.routine_generation_duration_seconds.measure({}, duration_seconds)
    rescue StandardError => e
      log_metrics_error("record_routine_generation", e)
    end

    # Circuit breaker metrics
    def record_circuit_state(circuit_name, state)
      return unless metrics_enabled?

      state_value = case state
                    when :closed then 0
                    when :open then 1
                    when :half_open then 2
                    else 0
                    end

      Yabeda.repstack.circuit_breaker_state.set({ circuit_name: circuit_name.to_s }, state_value)
    rescue StandardError => e
      log_metrics_error("record_circuit_state", e)
    end

    def record_circuit_trip(circuit_name)
      return unless metrics_enabled?

      Yabeda.repstack.circuit_breaker_trips_total.increment({ circuit_name: circuit_name.to_s })
    rescue StandardError => e
      log_metrics_error("record_circuit_trip", e)
    end

    # Rate limiting metrics
    def record_rate_limit_hit(throttle_name)
      return unless metrics_enabled?

      Yabeda.repstack.rate_limit_hits_total.increment({ throttle_name: throttle_name.to_s })
    rescue StandardError => e
      log_metrics_error("record_rate_limit_hit", e)
    end

    # Database metrics
    def record_db_query(operation, duration_seconds)
      return unless metrics_enabled?

      Yabeda.database.query_duration_seconds.measure({ operation: operation.to_s }, duration_seconds)
    rescue StandardError => e
      log_metrics_error("record_db_query", e)
    end

    def update_connection_pool_metrics
      return unless metrics_enabled?

      pool = ActiveRecord::Base.connection_pool
      Yabeda.database.connection_pool_size.set({}, pool.size)
      Yabeda.database.connection_pool_active.set({}, pool.connections.count(&:in_use?))
    rescue StandardError => e
      log_metrics_error("update_connection_pool_metrics", e)
    end

    # Timing helper
    def measure_time
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      [result, duration]
    end

    private

    def metrics_enabled?
      defined?(Yabeda) && Yabeda.respond_to?(:repstack)
    end

    def log_metrics_error(method_name, error)
      Rails.logger.debug("[MetricsService] #{method_name} failed: #{error.message}")
    end
  end
end
