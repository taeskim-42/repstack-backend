# frozen_string_literal: true

# Workout session tool handlers: start workout, record exercise, complete workout.
module ChatToolHandlers
  module WorkoutTools
    extend ActiveSupport::Concern

    private

    def handle_record_exercise(input)
      result = ChatRecordService.record_exercise(
        user: user,
        exercise_name: input["exercise_name"],
        weight: input["weight"],
        reps: input["reps"],
        sets: input["sets"] || 1
      )

      if result[:success]
        record_item = {
          exercise_name: input["exercise_name"],
          weight: input["weight"],
          reps: input["reps"],
          sets: input["sets"] || 1,
          recorded_at: Time.current.iso8601
        }

        msg = "기록했어요! #{input['exercise_name']}"
        msg += " #{input['weight']}kg" if input["weight"]
        msg += " #{input['reps']}회"
        msg += " #{input['sets']}세트" if input["sets"] && input["sets"] > 1
        msg += " 💪"

        success_response(
          message: msg,
          intent: "RECORD_EXERCISE",
          data: { records: [ record_item ], suggestions: [] }
        )
      else
        error_response(result[:error] || "기록 저장에 실패했어요.")
      end
    end

    def handle_complete_workout(input)
      today_routine = WorkoutRoutine.where(user_id: user.id)
                                     .where("created_at > ?", Time.current.beginning_of_day)
                                     .order(created_at: :desc)
                                     .first

      active_session = user.workout_sessions.where(end_time: nil).order(created_at: :desc).first
      completed_sets = 0
      total_volume   = 0
      exercises_count = 0

      if active_session
        completed_sets  = active_session.total_sets
        total_volume    = active_session.total_volume
        exercises_count = active_session.exercises_performed
        active_session.complete!
      end

      today_routine&.complete! unless today_routine&.is_completed
      mark_workout_completed

      notes = input["notes"]
      today_routine.update(notes: notes) if notes.present? && today_routine

      lines = []
      lines << "수고하셨어요! 🎉 오늘 운동 완료!"
      lines << ""

      if completed_sets > 0
        lines << "📊 **오늘의 운동 기록**"
        lines << "• 완료 세트: #{completed_sets}세트"
        lines << "• 수행 운동: #{exercises_count}종목"
        lines << "• 총 볼륨: #{total_volume.to_i}kg" if total_volume > 0
        lines << ""
      elsif today_routine
        lines << "📊 **오늘의 운동**"
        lines << "• #{today_routine.day_of_week}"
        lines << "• 예상 시간: #{today_routine.estimated_duration || 45}분"
        lines << ""
      end

      lines << "💬 **피드백을 남겨주세요!**"
      lines << ""
      lines << "오늘 운동 어떠셨어요? 자유롭게 말씀해주세요:"
      lines << ""
      lines << "예: \"적당했어\", \"좀 쉬웠어\", \"힘들었어\", \"스쿼트가 어려웠어\""

      success_response(
        message: lines.join("\n"),
        intent: "WORKOUT_COMPLETED",
        data: {
          routine_id: today_routine&.id,
          completed_sets: completed_sets,
          exercises_performed: exercises_count,
          total_volume: total_volume.to_i,
          suggestions: [ "적당했어", "좀 쉬웠어", "힘들었어", "너무 쉬웠어" ]
        }
      )
    end

    def mark_workout_completed
      profile = user.user_profile
      return unless profile

      factors = profile.fitness_factors || {}
      factors["last_workout_completed_at"] = Time.current.iso8601
      profile.update!(fitness_factors: factors)
    end
  end
end
