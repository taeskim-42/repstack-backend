source "https://rubygems.org"

gem "rails", "~> 8.1.2"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "thruster"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", require: false

# CORS
gem "rack-cors"

# Ruby 3.5+ default gem compatibility
gem "ostruct"

# GraphQL
gem "graphql"

# HTTP client for Claude API
gem "faraday"

# Authentication
gem "bcrypt", "~> 3.1.7"
gem "jwt"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Testing
  gem "rspec-rails", "~> 7.0"
  gem "rspec_junit_formatter"
  gem "factory_bot_rails"
  gem "faker"
  gem "shoulda-matchers"
  gem "webmock"
  gem "vcr"
  gem "simplecov", require: false
end

group :development do
  # Performance & Debugging
  gem "bullet" # N+1 query detection

  # Linting
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
  gem "rubocop-rspec", require: false
  gem "rubocop-rails-omakase", require: false
end

# Circuit Breaker for external API resilience
gem "circuitbox"

# Structured logging
gem "lograge"

# Rate limiting
gem "rack-attack"

# Metrics & Monitoring
gem "prometheus_exporter"        # Prometheus metrics
gem "yabeda"                     # Metrics collection framework
gem "yabeda-rails"               # Rails metrics
gem "yabeda-graphql"             # GraphQL metrics
gem "yabeda-prometheus"          # Prometheus adapter
gem "yabeda-puma-plugin"         # Puma metrics

# Distributed Tracing
gem "opentelemetry-sdk"
gem "opentelemetry-exporter-otlp"
gem "opentelemetry-instrumentation-all"

# AWS S3 for video uploads
gem "aws-sdk-s3", "~> 1.0"

# Background Job Processing
gem "sidekiq", "~> 7.0"
gem "sidekiq-cron", "~> 2.0"  # Periodic job scheduling
gem "redis", "~> 5.0"
gem "connection_pool", "~> 2.5"  # Pin to 2.x for Ruby 3.4 compatibility
gem "webrick"  # For worker health check endpoint

# Vector Database (pgvector)
gem "neighbor", "~> 0.5"           # pgvector for Ruby/Rails

# YouTube Transcript extraction (no API key needed)
gem "youtube-transcript-rb"

# Note: YouTube video metadata still uses yt-dlp (system command)
# Install with: brew install yt-dlp
