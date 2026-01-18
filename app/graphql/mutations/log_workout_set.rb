# frozen_string_literal: true

module Mutations
  class LogWorkoutSet < BaseMutation
    argument :session_id, ID, required: true
    argument :set_input, Types::WorkoutSetInputType, required: true

    field :workout_set, Types::WorkoutSetType, null: true
    field :errors, [String], null: false

    def resolve(session_id:, set_input:)
      user = context[:current_user]
      
      unless user
        return {
          workout_set: nil,
          errors: ['Authentication required']
        }
      end

      workout_session = user.workout_sessions.find_by(id: session_id)

      unless workout_session
        return {
          workout_set: nil,
          errors: ['Workout session not found']
        }
      end

      unless workout_session.active?
        return {
          workout_set: nil,
          errors: ['Workout session is not active']
        }
      end

      # Convert input to hash and set default weight unit
      set_attrs = set_input.to_h
      set_attrs[:weight_unit] ||= 'kg'

      workout_set = workout_session.workout_sets.build(set_attrs)

      if workout_set.save
        {
          workout_set: workout_set,
          errors: []
        }
      else
        {
          workout_set: nil,
          errors: workout_set.errors.full_messages
        }
      end
    rescue StandardError => e
      {
        workout_set: nil,
        errors: [e.message]
      }
    end

    private

    def ready?(set_input:, **args)
      weight_unit = set_input.weight_unit
      if weight_unit && !%w[kg lbs].include?(weight_unit)
        raise GraphQL::ExecutionError, 'Invalid weight unit. Must be kg or lbs'
      end

      true
    end
  end
end