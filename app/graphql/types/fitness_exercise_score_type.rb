# frozen_string_literal: true

module Types
  class FitnessExerciseScoreType < Types::BaseObject
    description "Score details for a single fitness test exercise"

    field :count, Integer, null: false,
      description: "Number of reps completed"
    field :tier, String, null: false,
      description: "Performance tier (poor/fair/good/excellent/elite)"
    field :tier_korean, String, null: false,
      description: "Performance tier in Korean"
    field :points, Integer, null: false,
      description: "Points earned (1-5)"
  end
end
