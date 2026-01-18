# frozen_string_literal: true

module Types
  class UserType < Types::BaseObject
    field :id, ID, null: false
    field :email, String, null: false
    field :name, String, null: false
    field :created_at, String, null: false
    field :updated_at, String, null: false

    # Associations
    field :user_profile, Types::UserProfileType, null: true
    field :workout_sessions, [Types::WorkoutSessionType], null: false
    field :workout_routines, [Types::WorkoutRoutineType], null: false

    # Computed fields
    field :current_workout_session, Types::WorkoutSessionType, null: true
    field :has_active_workout, Boolean, null: false
    field :total_workout_sessions, Integer, null: false

    def created_at
      object.created_at.iso8601
    end

    def updated_at
      object.updated_at.iso8601
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