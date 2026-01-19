# frozen_string_literal: true

module Mutations
  class CreateWorkoutSession < BaseMutation
    argument :name, String, required: false

    field :workout_session, Types::WorkoutSessionType, null: true
    field :errors, [String], null: false

    def resolve(name: nil)
      with_error_handling(workout_session: nil) do
        user = authenticate!

        if user.has_active_workout?
          return error_response("You already have an active workout session", workout_session: nil)
        end

        workout_session = user.workout_sessions.create!(
          name: name,
          start_time: Time.current
        )

        success_response(workout_session: workout_session)
      end
    end
  end
end