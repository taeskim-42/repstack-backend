# frozen_string_literal: true

module Types
  class RoutineExerciseType < Types::BaseObject
    field :id, ID, null: false
    field :exercise_name, String, null: false
    field :target_muscle, String, null: true
    field :order_index, Integer, null: false
    field :sets, Integer, null: true
    field :reps, Integer, null: true
    field :weight, Float, null: true
    field :weight_description, String, null: true
    field :bpm, Integer, null: true
    field :rest_duration_seconds, Integer, null: true
    field :range_of_motion, String, null: true
    field :how_to, String, null: true
    field :purpose, String, null: true
    field :created_at, String, null: false
    field :updated_at, String, null: false
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

    def created_at
      object.created_at.iso8601
    end

    def updated_at
      object.updated_at.iso8601
    end
  end
end