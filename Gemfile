source "https://rubygems.org"

gem "rails", "~> 8.1.2"
# gem "pg", "~> 1.1"  # Disabled - no database needed
gem "puma", ">= 5.0"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", require: false

# CORS
gem "rack-cors"

# GraphQL
gem "graphql"

# HTTP client for Claude API
gem "faraday"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
end
