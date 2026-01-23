# frozen_string_literal: true

module Types
  class UserType < Types::BaseObject
    field :id, ID, null: false
    field :email, String, null: false
    field :name, String, null: true
    field :created_at, String, null: false
    field :updated_at, String, null: false

    # Associations with pagination support to prevent loading too much data
    field :user_profile, Types::UserProfileType, null: true
    field :workout_sessions, [ Types::WorkoutSessionType ], null: false do
      argument :limit, Integer, required: false, default_value: 10
    end
    field :workout_routines, [ Types::WorkoutRoutineType ], null: false do
      argument :limit, Integer, required: false, default_value: 10
    end

    # Computed fields
    field :current_workout_session, Types::WorkoutSessionType, null: true
    field :has_active_workout, Boolean, null: false
    field :total_workout_sessions, Integer, null: false

    MAX_LIMIT = 100

    def created_at
      object.created_at.iso8601
    end

    def updated_at
      object.updated_at.iso8601
    end

    def workout_sessions(limit: 10)
      object.workout_sessions
            .includes(:workout_sets)
            .order(created_at: :desc)
            .limit([ limit, MAX_LIMIT ].min)
    end

    def workout_routines(limit: 10)
      object.workout_routines
            .includes(:routine_exercises)
            .order(created_at: :desc)
            .limit([ limit, MAX_LIMIT ].min)
    end

    def current_workout_session
      object.current_workout_session
    end

    def has_active_workout
      object.has_active_workout?
    end

    def total_workout_sessions
      object.total_workout_sessions
    end
  end
end
