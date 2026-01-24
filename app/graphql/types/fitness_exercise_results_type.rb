# frozen_string_literal: true

module Types
  class FitnessExerciseResultsType < Types::BaseObject
    description "Detailed results for each fitness test exercise"

    field :pushup, Types::FitnessExerciseScoreType, null: true
    field :squat, Types::FitnessExerciseScoreType, null: true
    field :pullup, Types::FitnessExerciseScoreType, null: true
  end
end
