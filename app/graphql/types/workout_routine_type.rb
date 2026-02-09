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
    field :estimated_duration_minutes, Integer, null: false, description: "Estimated duration in minutes (alias with fallback)"
    field :is_completed, Boolean, null: false
    field :completed_at, String, null: true
    field :generated_at, String, null: false
    field :created_at, String, null: false
    field :updated_at, String, null: false
    field :routine_exercises, [ Types::RoutineExerciseType ], null: false
    field :user, Types::UserType, null: false
    field :generation_source, String, null: true, description: "How this routine was generated"
    field :training_program_id, ID, null: true
    field :is_today, Boolean, null: false, description: "Whether this is today's routine"
    field :is_editable, Boolean, null: false, description: "Whether this routine can be modified"

    # Computed fields
    field :total_exercises, Integer, null: false
    field :total_sets, Integer, null: false
    field :estimated_duration_formatted, String, null: true
    field :workout_summary, Types::WorkoutSummaryType, null: false
    field :day_name, String, null: false

    def estimated_duration_minutes
      object.estimated_duration || 45
    end

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

    def is_today
      program = object.training_program
      return false unless program&.started_at

      today = Date.current
      days_since_start = (today - program.started_at.to_date).to_i
      current_week = (days_since_start / 7) + 1
      current_day_of_week = today.cwday # 1=Monday

      object.week_number == current_week && object.day_number == current_day_of_week
    end

    def is_editable
      is_today && !object.is_completed
    end
  end
end
