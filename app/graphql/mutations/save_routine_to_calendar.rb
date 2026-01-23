# frozen_string_literal: true

module Mutations
  class SaveRoutineToCalendar < BaseMutation
    description "Save an AI-generated routine to the calendar for a specific day"

    argument :routine_id, String, required: false, description: "Original routine ID (for reference)"
    argument :day_of_week, Integer, required: true, description: "Day of week (1=Monday ~ 7=Sunday)"
    argument :week_offset, Integer, required: false, default_value: 0, description: "Week offset (0=this week, 1=next week)"
    argument :estimated_duration, Integer, required: false, description: "Estimated duration in minutes"
    argument :exercises, [ Types::RoutineExerciseInputType ], required: true, description: "Exercises in the routine"

    field :success, Boolean, null: false
    field :saved_routine, Types::SavedRoutineType, null: true
    field :error, String, null: true

    def resolve(day_of_week:, exercises:, routine_id: nil, week_offset: 0, estimated_duration: nil)
      authenticate_user!

      # Validate day_of_week
      unless (1..7).cover?(day_of_week)
        return error_response("요일은 1(월요일)부터 7(일요일) 사이여야 합니다")
      end

      # Calculate target date
      target_date = Date.current.beginning_of_week + (day_of_week - 1).days + (week_offset * 7).days
      week_start = target_date.beginning_of_week

      # Check for existing routine on that day
      existing = current_user.workout_routines.find_by(
        day_of_week: day_name(day_of_week),
        day_number: day_of_week,
        is_completed: false
      )

      if existing && existing.generated_at >= week_start.beginning_of_day
        return error_response("해당 요일에 이미 루틴이 있습니다. 기존 루틴을 삭제하거나 완료해주세요.")
      end

      # Create the routine
      profile = current_user.user_profile
      routine = current_user.workout_routines.create!(
        level: profile&.current_level || "beginner",
        week_number: profile&.week_number || 1,
        day_number: day_of_week,
        day_of_week: day_name(day_of_week),
        estimated_duration: estimated_duration,
        generated_at: Time.current,
        is_completed: false
      )

      # Create exercises
      exercises.each do |exercise_input|
        routine.routine_exercises.create!(
          exercise_name: exercise_input[:exercise_name],
          order_index: exercise_input[:order_index],
          sets: exercise_input[:sets],
          reps: exercise_input[:reps],
          weight: exercise_input[:weight],
          weight_description: exercise_input[:weight_description],
          target_muscle: exercise_input[:target_muscle],
          bpm: exercise_input[:bpm],
          rest_duration_seconds: exercise_input[:rest_duration_seconds],
          range_of_motion: exercise_input[:range_of_motion],
          how_to: exercise_input[:how_to],
          purpose: exercise_input[:purpose]
        )
      end

      # Build saved routine response
      saved_routine = {
        id: routine.id,
        day_of_week: day_of_week,
        week_start_date: week_start.strftime("%Y-%m-%d"),
        routine: routine,
        created_at: routine.created_at
      }

      {
        success: true,
        saved_routine: saved_routine,
        error: nil
      }
    rescue GraphQL::ExecutionError
      raise
    rescue ActiveRecord::RecordInvalid => e
      error_response("루틴 저장 실패: #{e.message}")
    rescue StandardError => e
      Rails.logger.error("SaveRoutineToCalendar error: #{e.message}")
      error_response("루틴 저장 중 오류 발생")
    end

    private

    def error_response(message)
      {
        success: false,
        saved_routine: nil,
        error: message
      }
    end

    def day_name(day_number)
      %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday][day_number - 1]
    end
  end
end
