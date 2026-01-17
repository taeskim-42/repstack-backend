# frozen_string_literal: true

module Types
  class ExerciseType < Types::BaseObject
    field :exercise_name, String, null: false
    field :target_muscle, String, null: false
    field :sets, Integer, null: false
    field :reps, Integer, null: false
    field :weight, Float, null: true
    field :weight_description, String, null: true
    field :bpm, Integer, null: true
    field :rest_duration_seconds, Integer, null: true
    field :range_of_motion, String, null: true
    field :how_to, String, null: true
    field :purpose, String, null: true
  end
end
