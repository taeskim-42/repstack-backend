module Mutations
  class StartWorkoutSession < BaseMutation
    argument :name, String, required: false
    argument :notes, String, required: false

    field :workout_session, Types::WorkoutSessionType, null: true
    field :errors, [String], null: false

    def resolve(name: nil, notes: nil)
      user = context[:current_user]
      
      unless user
        return {
          workout_session: nil,
          errors: ['Authentication required']
        }
      end

      # Check if user already has an active session
      if user.has_active_workout?
        return {
          workout_session: nil,
          errors: ['You already have an active workout session']
        }
      end

      workout_session = user.workout_sessions.build(
        name: name,
        start_time: Time.current,
        notes: notes
      )

      if workout_session.save
        {
          workout_session: workout_session,
          errors: []
        }
      else
        {
          workout_session: nil,
          errors: workout_session.errors.full_messages
        }
      end
    rescue StandardError => e
      {
        workout_session: nil,
        errors: [e.message]
      }
    end
  end
end