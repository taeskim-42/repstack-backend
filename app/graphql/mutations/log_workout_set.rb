# frozen_string_literal: true

module Mutations
  class LogWorkoutSet < BaseMutation
    argument :session_id, ID, required: true
    argument :set_input, Types::WorkoutSetInputType, required: true

    field :workout_set, Types::WorkoutSetType, null: true
    field :errors, [String], null: false

    VALID_WEIGHT_UNITS = %w[kg lbs].freeze

    def resolve(session_id:, set_input:)
      with_error_handling(workout_set: nil) do
        user = authenticate!

        workout_session = user.workout_sessions.find_by(id: session_id)
        return error_response("Workout session not found", workout_set: nil) unless workout_session
        return error_response("Workout session is not active", workout_set: nil) unless workout_session.active?

        set_attrs = set_input.to_h
        set_attrs[:weight_unit] ||= "kg"

        workout_set = workout_session.workout_sets.create!(set_attrs)
        success_response(workout_set: workout_set)
      end
    end

    private

    def ready?(set_input:, **args)
      weight_unit = set_input.weight_unit
      if weight_unit && !VALID_WEIGHT_UNITS.include?(weight_unit)
        raise GraphQL::ExecutionError, "Invalid weight unit. Must be: #{VALID_WEIGHT_UNITS.join(', ')}"
      end
      true
    end
  end
end