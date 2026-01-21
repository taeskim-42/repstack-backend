# frozen_string_literal: true

module Mutations
  class AddExerciseToRoutine < BaseMutation
    description "Add an exercise to an existing routine"

    argument :routine_id, ID, required: true, description: "Target routine ID"
    argument :exercise_id, String, required: false, description: "Exercise ID from catalog (e.g., EX_CH01)"
    argument :exercise_name, String, required: false, description: "Custom exercise name"
    argument :sets, Integer, required: false, default_value: 3, description: "Number of sets"
    argument :reps, Integer, required: false, default_value: 10, description: "Number of reps"
    argument :weight, Float, required: false, description: "Weight in kg"
    argument :target_muscle, String, required: false, description: "Target muscle group"
    argument :order_index, Integer, required: false, description: "Order position (defaults to last)"

    field :success, Boolean, null: false
    field :routine, Types::WorkoutRoutineType, null: true
    field :added_exercise, Types::RoutineExerciseType, null: true
    field :error, String, null: true

    def resolve(routine_id:, exercise_id: nil, exercise_name: nil, sets: 3, reps: 10, weight: nil, target_muscle: nil, order_index: nil)
      authenticate_user!

      unless exercise_id.present? || exercise_name.present?
        return error_response("exercise_id 또는 exercise_name 중 하나는 필수입니다")
      end

      # Find routine
      routine = current_user.workout_routines.find_by(id: routine_id)
      return error_response("루틴을 찾을 수 없습니다") unless routine

      # Check if routine is already completed
      return error_response("완료된 루틴에는 운동을 추가할 수 없습니다", routine) if routine.is_completed

      # Resolve exercise name
      resolved_name = resolve_exercise_name(exercise_id, exercise_name)
      resolved_muscle = target_muscle || infer_target_muscle(resolved_name)

      # Determine order index
      final_order = order_index || (routine.routine_exercises.maximum(:order_index) || -1) + 1

      # Create exercise
      exercise = routine.routine_exercises.create!(
        exercise_name: resolved_name,
        order_index: final_order,
        sets: sets,
        reps: reps,
        weight: weight,
        target_muscle: resolved_muscle,
        rest_duration_seconds: 60
      )

      # Reorder if necessary
      reorder_exercises(routine, final_order, exercise.id) if order_index

      {
        success: true,
        routine: routine.reload,
        added_exercise: exercise,
        error: nil
      }
    rescue GraphQL::ExecutionError
      raise
    rescue ActiveRecord::RecordInvalid => e
      error_response("운동 추가 실패: #{e.message}")
    rescue StandardError => e
      Rails.logger.error("AddExerciseToRoutine error: #{e.message}")
      error_response("운동 추가 중 오류 발생")
    end

    private

    def error_response(message, routine = nil)
      {
        success: false,
        routine: routine,
        added_exercise: nil,
        error: message
      }
    end

    def resolve_exercise_name(exercise_id, exercise_name)
      return exercise_name if exercise_name.present?

      # Look up from exercise catalog if exercise_id provided
      if exercise_id.present?
        exercise_info = lookup_exercise_by_id(exercise_id)
        return exercise_info[:name] if exercise_info
      end

      raise ArgumentError, "운동 이름을 확인할 수 없습니다"
    end

    def lookup_exercise_by_id(exercise_id)
      return nil unless defined?(AiTrainer::Constants::EXERCISES)

      AiTrainer::Constants::EXERCISES.each_value do |muscle_data|
        muscle_data[:exercises].each do |exercise|
          return exercise if exercise[:id] == exercise_id
        end
      end

      nil
    end

    def infer_target_muscle(exercise_name)
      name_lower = exercise_name.downcase

      muscle_mappings = {
        "chest" => %w[벤치 푸시업 체스트 플라이 딥스],
        "back" => %w[풀업 로우 렛풀 데드리프트 턱걸이],
        "shoulders" => %w[숄더 프레스 레이즈 어깨],
        "legs" => %w[스쿼트 런지 레그 프레스 컬 익스텐션],
        "arms" => %w[컬 바이셉 트라이셉 삼두 이두],
        "core" => %w[플랭크 크런치 싯업 복근 코어]
      }

      muscle_mappings.each do |muscle, keywords|
        return muscle if keywords.any? { |kw| name_lower.include?(kw) }
      end

      "other"
    end

    def reorder_exercises(routine, inserted_at, new_exercise_id)
      routine.routine_exercises
             .where("order_index >= ? AND id != ?", inserted_at, new_exercise_id)
             .update_all("order_index = order_index + 1")
    end
  end
end
