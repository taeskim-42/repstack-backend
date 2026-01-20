# frozen_string_literal: true

module Types
  class WorkoutSessionType < Types::BaseObject
    field :id, ID, null: false
    field :name, String, null: true
    field :start_time, String, null: false
    field :end_time, String, null: true
    field :status, String, null: true, description: "Session status (pending, in_progress, completed)"
    field :total_duration, Integer, null: true, description: "Total duration in seconds (from DB)"
    field :notes, String, null: true
    field :created_at, String, null: false
    field :updated_at, String, null: false
    field :workout_sets, [Types::WorkoutSetType], null: false
    field :user, Types::UserType, null: false

    # Computed fields
    field :active, Boolean, null: false
    field :completed, Boolean, null: false
    field :duration_in_seconds, Integer, null: true
    field :duration_formatted, String, null: true
    field :total_sets, Integer, null: false
    field :exercises_performed, Integer, null: false
    field :total_volume, Float, null: false

    def start_time
      object.start_time.iso8601
    end

    def end_time
      object.end_time&.iso8601
    end

    def created_at
      object.created_at.iso8601
    end

    def updated_at
      object.updated_at.iso8601
    end

    def active
      object.active?
    end

    def completed
      object.completed?
    end

    def duration_in_seconds
      object.duration_in_seconds
    end

    def duration_formatted
      object.duration_formatted
    end

    def total_sets
      object.total_sets
    end

    def exercises_performed
      object.exercises_performed
    end

    def total_volume
      object.total_volume
    end
  end
end