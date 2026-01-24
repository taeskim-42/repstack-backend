require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Use SECRET_KEY_BASE environment variable
  config.secret_key_base = ENV["SECRET_KEY_BASE"]

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings.
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Cache assets for far-future expiry.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Log level
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Use memory cache store (no database required)
  config.cache_store = :memory_store

  # Use Sidekiq for Active Job if Redis is configured, otherwise inline
  config.active_job.queue_adapter = ENV["REDIS_URL"].present? ? :sidekiq : :inline

  # Enable locale fallbacks for I18n.
  config.i18n.fallbacks = true

  # Allow all hosts for Railway deployment
  config.hosts.clear
end
