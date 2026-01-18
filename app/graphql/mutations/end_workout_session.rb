# frozen_string_literal: true

module Mutations
  class EndWorkoutSession < BaseMutation
    argument :id, ID, required: true

    field :workout_session, Types::WorkoutSessionType, null: true
    field :errors, [String], null: false

    def resolve(id:)
      user = context[:current_user]
      
      unless user
        return {
          workout_session: nil,
          errors: ['Authentication required']
        }
      end

      workout_session = user.workout_sessions.find_by(id: id)

      unless workout_session
        return {
          workout_session: nil,
          errors: ['Workout session not found']
        }
      end

      unless workout_session.active?
        return {
          workout_session: nil,
          errors: ['Workout session is already completed']
        }
      end

      workout_session.complete!

      {
        workout_session: workout_session,
        errors: []
      }
    rescue StandardError => e
      {
        workout_session: nil,
        errors: [e.message]
      }
    end
  end
end