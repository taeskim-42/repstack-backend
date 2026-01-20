source "https://rubygems.org"

gem "rails", "~> 8.1.2"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "thruster"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", require: false

# CORS
gem "rack-cors"

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
  gem "rspec-rails", "~> 8.0"
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