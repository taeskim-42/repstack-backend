# frozen_string_literal: true

require "simplecov"
SimpleCov.start "rails" do
  add_filter "/spec/"
  add_filter "/config/"
  add_filter "/vendor/"

  add_group "Services", "app/services"
  add_group "GraphQL", "app/graphql"
  add_group "Models", "app/models"

  # CI environment may have lower coverage due to external service mocks
  minimum_coverage ENV.fetch("COVERAGE_MINIMUM", 70).to_i
  minimum_coverage_by_file 50
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Run specs in random order to surface order dependencies
  config.order = :random
  Kernel.srand config.seed

  # Focus on specific tests when debugging
  config.filter_run_when_matching :focus

  # Print the 10 slowest examples
  config.profile_examples = 10
end
