# frozen_string_literal: true

require "simplecov"
SimpleCov.start "rails" do
  add_filter "/spec/"
  add_filter "/config/"
  add_filter "/vendor/"

  # Filter out GraphQL base classes (no logic to test)
  add_filter "app/graphql/types/base_scalar.rb"
  add_filter "app/graphql/types/base_union.rb"
  add_filter "app/graphql/resolvers/base_resolver.rb"

  # Filter out pure GraphQL input/output types (field definitions only, no methods)
  add_filter "app/graphql/types/body_info_input_type.rb"
  add_filter "app/graphql/types/chat_input_type.rb"
  add_filter "app/graphql/types/chat_payload_type.rb"
  add_filter "app/graphql/types/condition_result_type.rb"
  add_filter "app/graphql/types/feedback_result_type.rb"
  add_filter "app/graphql/types/level_test_input_type.rb"
  add_filter "app/graphql/types/level_test_result_type.rb"
  add_filter "app/graphql/types/routine_type.rb"
  add_filter "app/graphql/types/sync_offline_records_input_type.rb"
  add_filter "app/graphql/types/sync_offline_records_payload_type.rb"
  add_filter "app/graphql/types/workout_record_result_type.rb"
  add_filter "app/graphql/types/workout_set_input_type.rb"
  add_filter "app/graphql/types/add_exercise_to_routine_input_type.rb"
  add_filter "app/graphql/types/save_routine_to_calendar_input_type.rb"
  add_filter "app/graphql/types/exercise_type.rb"

  # Filter out Rails default files
  add_filter "app/jobs/application_job.rb"

  # Filter out deprecated model concern
  add_filter "app/models/concerns/exception_handler.rb"

  # Filter out infrastructure files (config/error handling/base classes)
  add_filter "app/graphql/repstack_backend_schema.rb"
  add_filter "app/graphql/mutations/base_mutation.rb"
  add_filter "app/controllers/concerns/exception_handler.rb"
  add_filter "app/controllers/application_controller.rb"
  add_filter "app/controllers/graphql_controller.rb"

  add_group "Services", "app/services"
  add_group "GraphQL", "app/graphql"
  add_group "Models", "app/models"

  # In CI, don't fail on coverage threshold (report only)
  # Locally, enforce coverage thresholds
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
