# frozen_string_literal: true

module Mutations
  class AddWorkoutSet < BaseMutation
    description "Add a workout set to an active session"

    argument :session_id, ID, required: true
    argument :exercise_name, String, required: true
    argument :weight, Float, required: false
    argument :weight_unit, String, required: false
    argument :reps, Integer, required: false
    argument :duration_seconds, Integer, required: false
    argument :notes, String, required: false
    argument :target_muscle, String, required: false
    argument :rpe, Integer, required: false
    argument :set_number, Integer, required: false

    field :workout_set, Types::WorkoutSetType, null: true
    field :errors, [ String ], null: false

    VALID_WEIGHT_UNITS = %w[kg lbs].freeze

    def resolve(session_id:, exercise_name:, **args)
      with_error_handling(workout_set: nil) do
        user = authenticate!

        workout_session = user.workout_sessions.find_by(id: session_id)
        return error_response("Workout session not found", workout_set: nil) unless workout_session
        return error_response("Workout session is not active", workout_set: nil) unless workout_session.active?

        workout_set = workout_session.workout_sets.create!(
          exercise_name: exercise_name,
          weight: args[:weight],
          weight_unit: args[:weight_unit] || "kg",
          reps: args[:reps],
          duration_seconds: args[:duration_seconds],
          notes: args[:notes],
          target_muscle: args[:target_muscle],
          rpe: args[:rpe],
          set_number: args[:set_number]
        )

        MetricsService.record_workout_set_logged
        success_response(workout_set: workout_set)
      end
    end

    private

    def ready?(weight_unit: nil, **args)
      if weight_unit && !VALID_WEIGHT_UNITS.include?(weight_unit)
        raise GraphQL::ExecutionError, "Invalid weight unit. Must be: #{VALID_WEIGHT_UNITS.join(', ')}"
      end
      true
    end
  end
end
