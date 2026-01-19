# frozen_string_literal: true

require "spec_helper"
ENV["RAILS_ENV"] ||= "test"

require_relative "../config/environment"

# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "webmock/rspec"
require "vcr"

# Add additional requires below this line

# Load support files
Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |f| require f }

# Checks for pending migrations and applies them before tests are run
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  # Remove this line if you're not using ActiveRecord
  config.fixture_paths = [Rails.root.join("spec/fixtures")]

  # Use transactional fixtures
  config.use_transactional_fixtures = true

  # Infer spec type from file location
  config.infer_spec_type_from_file_location!

  # Filter Rails framework backtraces
  config.filter_rails_from_backtrace!

  # Include FactoryBot methods
  config.include FactoryBot::Syntax::Methods

  # Include GraphQL test helpers
  config.include GraphQL::TestHelpers, type: :graphql

  # Database cleaner
  config.before(:suite) do
    # Ensure factories are valid
    FactoryBot.lint if defined?(FactoryBot)
  end

  config.around(:each) do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end

# Shoulda Matchers configuration
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

# VCR configuration for recording HTTP interactions
VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Filter sensitive data
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] }

  # Allow localhost connections for test server
  config.ignore_localhost = true

  # Record mode - :new_episodes records new requests, uses cached for existing
  config.default_cassette_options = {
    record: :new_episodes,
    match_requests_on: [:method, :uri, :body]
  }
end

# WebMock configuration
WebMock.disable_net_connect!(allow_localhost: true)
