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
    field :days_until_eligible, Integer, null: true
  end
end
