# frozen_string_literal: true

module Internal
  class ExercisesController < BaseController
    # POST /internal/exercises/record
    def record
      result = ChatRecordService.record_exercise(
        user: @user,
        exercise_name: params[:exercise_name],
        weight: params[:weight],
        reps: params[:reps],
        sets: params[:sets] || 1
      )

      if result[:success]
        render_success(
          matched_exercise: result[:matched_exercise],
          original_input: result[:original_input],
          session_id: result[:session]&.id,
          sets_created: result[:sets]&.size || 0
        )
      else
        render_error(result[:error] || "기록 저장 실패")
      end
    end
  end
end
