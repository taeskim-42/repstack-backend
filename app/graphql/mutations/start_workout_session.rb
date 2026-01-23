# frozen_string_literal: true

module Mutations
  class StartWorkoutSession < BaseMutation
    description "Start a new workout session"

    argument :name, String, required: false
    argument :notes, String, required: false

    field :workout_session, Types::WorkoutSessionType, null: true
    field :errors, [ String ], null: false

    def resolve(name: nil, notes: nil)
      with_error_handling(workout_session: nil) do
        user = authenticate!

        if user.has_active_workout?
          return error_response("You already have an active workout session", workout_session: nil)
        end

        workout_session = user.workout_sessions.create!(
          name: name,
          start_time: Time.current,
          notes: notes
        )

        MetricsService.record_workout_session_created(success: true)
        success_response(workout_session: workout_session)
      rescue StandardError => e
        MetricsService.record_workout_session_created(success: false)
        raise e
      end
    end
  end
end
