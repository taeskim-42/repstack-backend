module Mutations
  class CompleteRoutine < BaseMutation
    argument :routine_id, ID, required: true

    field :workout_routine, Types::WorkoutRoutineType, null: true
    field :user_profile, Types::UserProfileType, null: true
    field :errors, [String], null: false

    def resolve(routine_id:)
      user = context[:current_user]
      
      unless user
        return {
          workout_routine: nil,
          user_profile: nil,
          errors: ['Authentication required']
        }
      end

      routine = user.workout_routines.find_by(id: routine_id)

      unless routine
        return {
          workout_routine: nil,
          user_profile: nil,
          errors: ['Routine not found']
        }
      end

      if routine.is_completed?
        return {
          workout_routine: nil,
          user_profile: nil,
          errors: ['Routine is already completed']
        }
      end

      routine.complete! # This will also advance the user's day

      {
        workout_routine: routine,
        user_profile: user.user_profile.reload,
        errors: []
      }
    rescue StandardError => e
      {
        workout_routine: nil,
        user_profile: nil,
        errors: [e.message]
      }
    end
  end
end