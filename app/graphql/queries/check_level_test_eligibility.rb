# frozen_string_literal: true

module Queries
  class CheckLevelTestEligibility < BaseQuery
    description "Check if the current user is eligible to take a level test"

    type Types::LevelTestEligibilityType, null: false

    def resolve
      authenticate_user!

      AiTrainer.check_test_eligibility(user: current_user)
    end
  end
end
