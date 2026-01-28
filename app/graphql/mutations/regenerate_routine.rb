# frozen_string_literal: true

module Mutations
  class RegenerateRoutine < BaseMutation
    description "Regenerate an existing routine with new exercises based on goal"

    argument :routine_id, ID, required: true, description: "Routine ID to regenerate"
    argument :goal, String, required: false, description: "Training goal (e.g., '등근육 키우고 싶음')"
    argument :keep_exercises, [String], required: false, description: "Exercise names to keep"
    argument :avoid_exercises, [String], required: false, description: "Exercise names to avoid"

    field :success, Boolean, null: false
    field :routine, Types::WorkoutRoutineType, null: true
    field :remaining_regenerations, Integer, null: true
    field :error, String, null: true

    def resolve(routine_id:, goal: nil, keep_exercises: nil, avoid_exercises: nil)
      authenticate_user!

      # Check rate limit
      rate_check = RoutineRateLimiter.check_and_increment!(
        user: current_user,
        action: :routine_regeneration
      )

      unless rate_check[:allowed]
        return error_response(rate_check[:error], remaining: 0)
      end

      # Find existing routine
      routine = current_user.workout_routines.find_by(id: routine_id)
      return error_response("루틴을 찾을 수 없습니다") unless routine

      # Check if routine is completed
      return error_response("완료된 루틴은 재생성할 수 없습니다") if routine.is_completed

      # Generate new routine
      result = AiTrainer::RoutineService.generate(
        user: current_user,
        day_of_week: routine.day_number,
        goal: goal,
        condition: build_condition_from_routine(routine)
      )

      return error_response("루틴 생성에 실패했습니다") unless result&.dig(:routine_id)

      # Update existing routine with new exercises
      update_routine_exercises(
        routine: routine,
        new_exercises: result[:exercises],
        keep_exercises: keep_exercises || [],
        avoid_exercises: avoid_exercises || []
      )

      # Update routine metadata
      routine.update!(
        workout_type: result[:training_type],
        estimated_duration: result[:estimated_duration_minutes]
      )

      {
        success: true,
        routine: routine.reload,
        remaining_regenerations: rate_check[:remaining],
        error: nil
      }
    rescue StandardError => e
      Rails.logger.error("RegenerateRoutine error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      error_response("루틴 재생성 중 오류가 발생했습니다")
    end

    private

    def error_response(message, remaining: nil)
      {
        success: false,
        routine: nil,
        remaining_regenerations: remaining,
        error: message
      }
    end

    def build_condition_from_routine(routine)
      # Try to get condition from the same day's condition log
      condition_log = current_user.condition_logs.find_by(date: routine.created_at.to_date)

      return nil unless condition_log

      {
        energy_level: condition_log.energy_level,
        stress_level: condition_log.stress_level,
        sleep_quality: condition_log.sleep_quality
      }
    end

    def update_routine_exercises(routine:, new_exercises:, keep_exercises:, avoid_exercises:)
      # Get existing exercises to potentially keep
      existing = routine.routine_exercises.index_by(&:exercise_name)

      # Delete existing exercises (except ones to keep)
      routine.routine_exercises.where.not(exercise_name: keep_exercises).destroy_all

      # Determine starting order index
      start_order = routine.routine_exercises.maximum(:order_index) || -1
      current_order = start_order + 1

      # Add new exercises
      new_exercises.each do |ex|
        # Skip if exercise is in avoid list
        next if avoid_exercises.include?(ex[:exercise_name])

        # Skip if already kept
        next if keep_exercises.include?(ex[:exercise_name])

        routine.routine_exercises.create!(
          exercise_name: ex[:exercise_name],
          order_index: current_order,
          sets: ex[:sets],
          reps: ex[:reps],
          target_muscle: ex[:target_muscle],
          rest_duration_seconds: ex[:rest_seconds] || 60,
          instructions: ex[:instructions],
          weight_suggestion: ex[:weight_description]
        )

        current_order += 1
      end

      # Reorder all exercises
      routine.routine_exercises.order(:order_index).each_with_index do |exercise, idx|
        exercise.update_column(:order_index, idx)
      end
    end
  end
end
