# frozen_string_literal: true

module Types
  class LevelTestEligibilityType < Types::BaseObject
    description "User's eligibility status for taking a level test"

    field :eligible, Boolean, null: false
    field :reason, String, null: true, description: "Reason if not eligible"
    field :current_level, Integer, null: true
    field :target_level, Integer, null: true
    field :target_tier, String, null: true
    field :current_workouts, Integer, null: true
    field :required_workouts, Integer, null: true
    field :remaining_workouts, Integer, null: true, description: "Workouts remaining before eligible"
    field :days_until_eligible, Integer, null: true

    def remaining_workouts
      return nil unless object[:required_workouts] && object[:current_workouts]

      [ object[:required_workouts] - object[:current_workouts], 0 ].max
    end
  end
end
