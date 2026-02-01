# frozen_string_literal: true

module Mutations
  class DeleteRoutine < BaseMutation
    description "Delete a workout routine"

    argument :routine_id, ID, required: true

    field :success, Boolean, null: false
    field :deleted_routine_id, ID, null: true
    field :errors, [ String ], null: false

    def resolve(routine_id:)
      with_error_handling(success: false, deleted_routine_id: nil) do
        user = authenticate!

        routine = user.workout_routines.find_by(id: routine_id)
        return error_response("루틴을 찾을 수 없습니다", success: false, deleted_routine_id: nil) unless routine

        # Completed routines cannot be deleted (preserve workout history)
        if routine.is_completed?
          return error_response("완료된 루틴은 삭제할 수 없습니다", success: false, deleted_routine_id: nil)
        end

        routine.destroy!

        success_response(success: true, deleted_routine_id: routine_id)
      end
    end
  end
end
