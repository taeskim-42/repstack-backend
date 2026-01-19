# frozen_string_literal: true

module Mutations
  class EndWorkoutSession < BaseMutation
    description "End an active workout session"

    argument :id, ID, required: true

    field :workout_session, Types::WorkoutSessionType, null: true
    field :errors, [String], null: false

    def resolve(id:)
      with_error_handling(workout_session: nil) do
        user = authenticate!

        workout_session = user.workout_sessions.find_by(id: id)
        return error_response("Workout session not found", workout_session: nil) unless workout_session
        return error_response("Workout session is already completed", workout_session: nil) unless workout_session.active?

        workout_session.complete!
        success_response(workout_session: workout_session)
      end
    end
  end
end