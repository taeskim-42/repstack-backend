# frozen_string_literal: true

module Types
  class LevelTestResultType < Types::BaseObject
    description "Result of level assessment test"

    field :success, Boolean, null: false, description: "Whether the test was successful"
    field :level, Types::TrainingLevelEnum, null: true, description: "Determined training level"
    field :confidence, Float, null: true, description: "Confidence score 0-1"
    field :reasoning, String, null: true, description: "AI reasoning for the level"
    field :fitness_factors, Types::FitnessFactorsType, null: true, description: "Detailed fitness factors"
    field :recommendations, [String], null: true, description: "Training recommendations"
    field :error, String, null: true, description: "Error message if failed"
  end
end
