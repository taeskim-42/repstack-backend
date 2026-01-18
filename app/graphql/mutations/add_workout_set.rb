module Mutations
  class AddWorkoutSet < BaseMutation
    argument :session_id, ID, required: true
    argument :exercise_name, String, required: true
    argument :weight, Float, required: false
    argument :weight_unit, String, required: false
    argument :reps, Integer, required: false
    argument :duration_seconds, Integer, required: false
    argument :notes, String, required: false

    field :workout_set, Types::WorkoutSetType, null: true
    field :errors, [String], null: false

    def resolve(session_id:, exercise_name:, **args)
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

      workout_set = workout_session.workout_sets.build(
        exercise_name: exercise_name,
        weight: args[:weight],
        weight_unit: args[:weight_unit] || 'kg',
        reps: args[:reps],
        duration_seconds: args[:duration_seconds],
        notes: args[:notes]
      )

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

    def ready?(weight_unit: nil, **args)
      if weight_unit && !%w[kg lbs].include?(weight_unit)
        raise GraphQL::ExecutionError, 'Invalid weight unit. Must be kg or lbs'
      end

      true
    end
  end
end