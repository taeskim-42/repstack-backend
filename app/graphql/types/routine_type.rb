# frozen_string_literal: true

module Types
  class RoutineType < Types::BaseObject
    field :workout_type, String, null: false
    field :day_of_week, String, null: false
    field :estimated_duration, Integer, null: true
    field :exercises, [ Types::ExerciseType ], null: false
  end
end
