# frozen_string_literal: true

module Types
  class PassConditionExerciseType < Types::BaseObject
    description "Exercise requirement for passing the test"

    field :exercise, String, null: false
    field :weight_kg, Float, null: false
    field :reps, Integer, null: false
  end
end
