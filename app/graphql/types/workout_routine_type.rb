# frozen_string_literal: true

module Types
  class WorkoutRoutineType < Types::BaseObject
    field :id, ID, null: false
    field :level, String, null: false
    field :week_number, Integer, null: false
    field :day_number, Integer, null: false
    field :workout_type, String, null: true
    field :day_of_week, String, null: true
    field :estimated_duration, Integer, null: true
    field :is_completed, Boolean, null: false
    field :completed_at, String, null: true
    field :generated_at, String, null: false
    field :created_at, String, null: false
    field :updated_at, String, null: false
    field :routine_exercises, [ Types::RoutineExerciseType ], null: false
    field :user, Types::UserType, null: false

    # Computed fields
    field :total_exercises, Integer, null: false
    field :total_sets, Integer, null: false
    field :estimated_duration_formatted, String, null: true
    field :workout_summary, Types::WorkoutSummaryType, null: false
    field :day_name, String, null: false

    def completed_at
      object.completed_at&.iso8601
    end

    def generated_at
      object.generated_at.iso8601
    end

    def created_at
      object.created_at.iso8601
    end

    def updated_at
      object.updated_at.iso8601
    end

    def total_exercises
      object.total_exercises
    end

    def total_sets
      object.total_sets
    end

    def estimated_duration_formatted
      object.estimated_duration_formatted
    end

    def workout_summary
      object.workout_summary
    end

    def day_name
      object.day_name
    end
  end
end
