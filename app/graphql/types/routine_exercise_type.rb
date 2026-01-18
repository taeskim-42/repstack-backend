# frozen_string_literal: true

module Types
  class RoutineExerciseType < Types::BaseObject
    field :id, ID, null: false
    field :exercise_name, String, null: false
    field :target_muscle, String, null: false
    field :order_index, Integer, null: false
    field :sets, Integer, null: false
    field :reps, Integer, null: false
    field :weight, Float, null: true
    field :weight_description, String, null: true
    field :bpm, Integer, null: true
    field :rest_duration_seconds, Integer, null: false
    field :range_of_motion, String, null: false
    field :how_to, String, null: false
    field :purpose, String, null: false
    field :workout_routine, Types::WorkoutRoutineType, null: false

    # Computed fields
    field :estimated_exercise_duration, Integer, null: false
    field :rest_duration_formatted, String, null: true
    field :is_cardio, Boolean, null: false
    field :is_strength, Boolean, null: false
    field :exercise_summary, String, null: false
    field :target_muscle_group, String, null: false

    def estimated_exercise_duration
      object.estimated_exercise_duration
    end

    def rest_duration_formatted
      object.rest_duration_formatted
    end

    def is_cardio
      object.is_cardio?
    end

    def is_strength
      object.is_strength?
    end

    def exercise_summary
      object.exercise_summary
    end

    def target_muscle_group
      object.target_muscle_group
    end
  end
end