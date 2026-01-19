# frozen_string_literal: true

module Mutations
  class CompleteRoutine < BaseMutation
    description "Mark a workout routine as completed and advance user's progress"

    argument :routine_id, ID, required: true

    field :workout_routine, Types::WorkoutRoutineType, null: true
    field :user_profile, Types::UserProfileType, null: true
    field :errors, [String], null: false

    def resolve(routine_id:)
      with_error_handling(workout_routine: nil, user_profile: nil) do
        user = authenticate!

        routine = user.workout_routines.find_by(id: routine_id)
        return error_response("Routine not found", workout_routine: nil, user_profile: nil) unless routine
        return error_response("Routine is already completed", workout_routine: nil, user_profile: nil) if routine.is_completed?

        routine.complete!

        success_response(
          workout_routine: routine,
          user_profile: user.user_profile&.reload
        )
      end
    end
  end
end