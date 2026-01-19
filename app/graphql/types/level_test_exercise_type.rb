# frozen_string_literal: true

module Types
  class LevelTestExerciseType < Types::BaseObject
    description "Exercise in a level test"

    field :order, Integer, null: false
    field :exercise_name, String, null: false
    field :exercise_type, String, null: false
    field :target_weight_kg, Float, null: false
    field :target_reps, Integer, null: false
    field :rest_minutes, Integer, null: false
    field :instructions, String, null: true
  end
end
