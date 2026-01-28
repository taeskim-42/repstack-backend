# frozen_string_literal: true

module Mutations
  class ReplaceExercise < BaseMutation
    description "Replace an exercise in a routine with AI-suggested alternative"

    argument :routine_id, ID, required: true, description: "Target routine ID"
    argument :exercise_index, Integer, required: true, description: "Index of exercise to replace (0-based)"
    argument :reason, String, required: false, description: "Reason for replacement (e.g., '어깨가 아파서', '장비 없음')"
    argument :target_muscle, String, required: false, description: "Keep same target muscle or specify new one"

    field :success, Boolean, null: false
    field :routine, Types::WorkoutRoutineType, null: true
    field :old_exercise, Types::RoutineExerciseType, null: true
    field :new_exercise, Types::RoutineExerciseType, null: true
    field :remaining_replacements, Integer, null: true
    field :error, String, null: true

    def resolve(routine_id:, exercise_index:, reason: nil, target_muscle: nil)
      authenticate_user!

      # Check rate limit
      rate_check = RoutineRateLimiter.check_and_increment!(
        user: current_user,
        action: :exercise_replacement
      )

      unless rate_check[:allowed]
        return error_response(rate_check[:error], remaining: 0)
      end

      # Find routine
      routine = current_user.workout_routines.find_by(id: routine_id)
      return error_response("루틴을 찾을 수 없습니다") unless routine

      # Find exercise to replace
      old_exercise = routine.routine_exercises.find_by(order_index: exercise_index)
      return error_response("해당 운동을 찾을 수 없습니다") unless old_exercise

      # Generate replacement using AI
      replacement = generate_replacement(
        routine: routine,
        old_exercise: old_exercise,
        reason: reason,
        target_muscle: target_muscle || old_exercise.target_muscle
      )

      return error_response(replacement[:error]) unless replacement[:success]

      # Update exercise
      old_exercise.update!(
        exercise_name: replacement[:exercise_name],
        sets: replacement[:sets],
        reps: replacement[:reps],
        rest_duration_seconds: replacement[:rest_seconds] || 60,
        instructions: replacement[:instructions],
        weight_suggestion: replacement[:weight_guide]
      )

      {
        success: true,
        routine: routine.reload,
        old_exercise: nil, # Already updated
        new_exercise: old_exercise.reload,
        remaining_replacements: rate_check[:remaining],
        error: nil
      }
    rescue StandardError => e
      Rails.logger.error("ReplaceExercise error: #{e.message}")
      error_response("운동 교체 중 오류가 발생했습니다")
    end

    private

    def error_response(message, remaining: nil)
      {
        success: false,
        routine: nil,
        old_exercise: nil,
        new_exercise: nil,
        remaining_replacements: remaining,
        error: message
      }
    end

    def generate_replacement(routine:, old_exercise:, reason:, target_muscle:)
      # Get other exercises in the routine to avoid duplicates
      other_exercises = routine.routine_exercises
                               .where.not(id: old_exercise.id)
                               .pluck(:exercise_name)

      prompt = build_replacement_prompt(
        old_exercise: old_exercise,
        reason: reason,
        target_muscle: target_muscle,
        other_exercises: other_exercises,
        user_level: current_user.user_profile&.numeric_level || 1
      )

      response = AiTrainer::LlmGateway.chat(
        prompt: prompt,
        task: :exercise_replacement,
        system: replacement_system_prompt
      )

      return { success: false, error: "AI 응답 실패" } unless response[:success]

      parse_replacement_response(response[:content])
    end

    def replacement_system_prompt
      <<~SYSTEM
        당신은 전문 피트니스 트레이너입니다. 사용자의 운동을 대체할 적절한 운동을 추천합니다.

        ## 원칙
        1. 같은 타겟 근육을 자극하는 대체 운동을 추천합니다
        2. 사용자가 말한 이유(부상, 장비 부족 등)를 고려합니다
        3. 이미 루틴에 있는 운동과 중복되지 않게 합니다

        ## 응답 형식
        반드시 JSON 형식으로만 응답하세요:
        ```json
        {
          "exercise_name": "대체 운동명",
          "target_muscle": "타겟 근육",
          "sets": 3,
          "reps": 10,
          "rest_seconds": 60,
          "instructions": "수행 방법",
          "weight_guide": "무게 가이드",
          "reason": "이 운동을 추천하는 이유"
        }
        ```
      SYSTEM
    end

    def build_replacement_prompt(old_exercise:, reason:, target_muscle:, other_exercises:, user_level:)
      tier = AiTrainer::Constants.tier_for_level(user_level)

      <<~PROMPT
        ## 교체할 운동
        - 운동명: #{old_exercise.exercise_name}
        - 타겟 근육: #{old_exercise.target_muscle}
        - 세트: #{old_exercise.sets}, 횟수: #{old_exercise.reps}

        ## 교체 이유
        #{reason || "다른 운동으로 변경 원함"}

        ## 조건
        - 사용자 레벨: #{tier}
        - 타겟 근육: #{target_muscle} (동일하게 유지)
        - 피해야 할 운동 (이미 루틴에 있음): #{other_exercises.join(", ")}

        위 조건에 맞는 대체 운동을 JSON으로 추천해주세요.
      PROMPT
    end

    def parse_replacement_response(content)
      json_str = extract_json(content)
      data = JSON.parse(json_str)

      {
        success: true,
        exercise_name: data["exercise_name"],
        target_muscle: data["target_muscle"],
        sets: data["sets"] || 3,
        reps: data["reps"] || 10,
        rest_seconds: data["rest_seconds"] || 60,
        instructions: data["instructions"],
        weight_guide: data["weight_guide"]
      }
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse replacement JSON: #{e.message}")
      { success: false, error: "응답 파싱 실패" }
    end

    def extract_json(text)
      if text =~ /```(?:json)?\s*(\{.*?\})\s*```/m
        Regexp.last_match(1)
      elsif text.include?("{")
        start_idx = text.index("{")
        end_idx = text.rindex("}")
        text[start_idx..end_idx] if start_idx && end_idx
      else
        text
      end
    end
  end
end
