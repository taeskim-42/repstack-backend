# frozen_string_literal: true

module Types
  class FitnessTestResultType < Types::BaseObject
    description "Result of basic fitness test (bodyweight exercises)"

    field :success, Boolean, null: false,
      description: "Whether the test was successfully processed"
    field :fitness_score, Integer, null: true,
      description: "Overall fitness score (0-100)"
    field :assigned_level, Integer, null: true,
      description: "Assigned numeric level (1-8)"
    field :assigned_tier, String, null: true,
      description: "Assigned tier (beginner/intermediate/advanced)"
    field :message, String, null: true,
      description: "Feedback message for the user"
    field :recommendations, [String], null: true,
      description: "Training recommendations based on results"
    field :exercise_results, Types::FitnessExerciseResultsType, null: true,
      description: "Detailed results for each exercise"
    field :errors, [String], null: false,
      description: "Error messages if any"
  end
end
