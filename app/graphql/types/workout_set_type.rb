# frozen_string_literal: true

module Types
  class WorkoutSetType < Types::BaseObject
    field :id, ID, null: false
    field :exercise_name, String, null: false
    field :weight, Float, null: true
    field :weight_unit, String, null: false
    field :reps, Integer, null: true
    field :duration_seconds, Integer, null: true
    field :notes, String, null: true
    field :set_number, Integer, null: true
    field :target_muscle, String, null: true
    field :rpe, Integer, null: true
    field :source, String, null: true, description: "Source of the set (app, chat, siri, watch, offline)"
    field :client_id, String, null: true, description: "Client-generated ID for offline sync"
    field :created_at, String, null: false
    field :updated_at, String, null: false
    field :workout_session, Types::WorkoutSessionType, null: false

    # Computed fields
    field :volume, Float, null: false
    field :is_timed_exercise, Boolean, null: false
    field :is_weighted_exercise, Boolean, null: false
    field :duration_formatted, String, null: true
    field :weight_in_kg, Float, null: true
    field :weight_in_lbs, Float, null: true

    def volume
      object.volume
    end

    def is_timed_exercise
      object.is_timed_exercise?
    end

    def is_weighted_exercise
      object.is_weighted_exercise?
    end

    def duration_formatted
      object.duration_formatted
    end

    def weight_in_kg
      object.weight_in_kg
    end

    def weight_in_lbs
      object.weight_in_lbs
    end

    def created_at
      object.created_at.iso8601
    end

    def updated_at
      object.updated_at.iso8601
    end
  end
end
