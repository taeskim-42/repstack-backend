# frozen_string_literal: true

module Mutations
  class StartLevelTest < BaseMutation
    description "Start a level-up test (승급 시험) for the current user"

    field :success, Boolean, null: false
    field :test, Types::LevelTestDetailType, null: true
    field :error, String, null: true

    def resolve
      authenticate_user!

      # Check eligibility
      eligibility = AiTrainer.check_test_eligibility(user: current_user)

      unless eligibility[:eligible]
        return {
          success: false,
          test: nil,
          error: eligibility[:reason]
        }
      end

      # Generate the test
      test = AiTrainer.generate_level_test(user: current_user)

      if test[:success] == false
        {
          success: false,
          test: nil,
          error: test[:error]
        }
      else
        {
          success: true,
          test: test,
          error: nil
        }
      end
    end
  end
end
