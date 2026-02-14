# frozen_string_literal: true

module Mutations
  class DeleteWorkoutSet < BaseMutation
    description "Delete a workout set from an active session (for undo)"

    argument :set_id, ID, required: true

    field :success, Boolean, null: false
    field :errors, [String], null: false

    def resolve(set_id:)
      with_error_handling(success: false) do
        user = authenticate!

        workout_set = WorkoutSet.joins(:workout_session)
          .where(workout_sessions: { user_id: user.id })
          .find_by(id: set_id)

        return error_response("Set not found", success: false) unless workout_set
        return error_response("Session is not active", success: false) unless workout_set.workout_session.active?

        workout_set.destroy!
        success_response(success: true)
      end
    end
  end
end
