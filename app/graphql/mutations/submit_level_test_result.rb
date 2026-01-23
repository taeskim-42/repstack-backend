# frozen_string_literal: true

module Mutations
  class SubmitLevelTestResult < BaseMutation
    description "Submit results for a level-up test (승급 시험)"

    argument :test_id, String, required: true, description: "The test ID from start_level_test"
    argument :exercises, [ Types::LevelTestExerciseResultInputType ], required: true,
      description: "Results for each exercise in the test"

    field :success, Boolean, null: false
    field :passed, Boolean, null: true
    field :new_level, Integer, null: true
    field :results, Types::LevelTestResultsType, null: true
    field :feedback, [ String ], null: true
    field :next_steps, [ String ], null: true
    field :error, String, null: true

    def resolve(test_id:, exercises:)
      authenticate_user!

      exercises_array = exercises.map { |e| e.to_h.deep_transform_keys { |k| k.to_s.underscore.to_sym } }

      test_results = {
        test_id: test_id,
        exercises: exercises_array
      }

      result = AiTrainer.evaluate_level_test(
        user: current_user,
        test_results: test_results
      )

      # Update user profile if passed
      if result[:passed] && current_user.user_profile
        current_user.user_profile.update!(
          numeric_level: result[:new_level],
          last_level_test_at: Time.current
        )
      end

      if result[:success] == false
        {
          success: false,
          passed: nil,
          new_level: nil,
          results: nil,
          feedback: nil,
          next_steps: nil,
          error: result[:error]
        }
      else
        {
          success: true,
          passed: result[:passed],
          new_level: result[:new_level],
          results: result[:results],
          feedback: result[:feedback],
          next_steps: result[:next_steps],
          error: nil
        }
      end
    end
  end
end
