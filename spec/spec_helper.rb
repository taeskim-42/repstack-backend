# frozen_string_literal: true

require "simplecov"
SimpleCov.start "rails" do
  add_filter "/spec/"
  add_filter "/config/"
  add_filter "/vendor/"

  add_group "Services", "app/services"
  add_group "GraphQL", "app/graphql"
  add_group "Models", "app/models"

  # In CI, don't fail on coverage threshold (report only)
  # Locally, enforce 80% coverage
  if ENV["CI"]
    minimum_coverage line: 0
    minimum_coverage_by_file line: 0
  else
    minimum_coverage 80
    minimum_coverage_by_file 70
  end
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
