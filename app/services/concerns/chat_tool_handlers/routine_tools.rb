# frozen_string_literal: true

# Routine-related tool handlers: generate, replace, add, delete exercise.
module ChatToolHandlers
  module RoutineTools
    extend ActiveSupport::Concern

    private

    def handle_generate_routine(input)
      profile = user.user_profile

      unless profile&.onboarding_completed_at.present? || profile&.numeric_level.present?
        if AiTrainer::LevelAssessmentService.needs_assessment?(user)
          return error_response("먼저 간단한 상담을 완료해주세요! 그래야 맞춤 루틴을 만들 수 있어요. 💬")
        else
          return error_response("프로필 설정이 완료되지 않았어요. 상담을 먼저 진행해주세요!")
        end
      end

      unless profile.numeric_level.present?
        Rails.logger.warn("[ChatService] User #{user.id} has onboarding completed but no numeric_level, setting default")
        profile.update!(numeric_level: 1, current_level: "beginner")
      end

      today_dow = Time.current.wday == 0 ? 7 : Time.current.wday
      today_routine = WorkoutRoutine.where(user_id: user.id)
                                    .where("created_at >= ?", Time.current.beginning_of_day)
                                    .where(day_number: today_dow)
                                    .where(is_completed: false)
                                    .order(created_at: :desc)
                                    .first

      if today_routine
        routine_data = format_existing_routine(today_routine)
        return success_response(
          message: "오늘의 루틴이에요! 💪\n\n특정 운동을 바꾸고 싶으면 'XX 대신 다른 운동'이라고 말씀해주세요.",
          intent: "GENERATE_ROUTINE",
          data: { routine: routine_data, suggestions: [] }
        )
      end

      program = user.active_training_program
      if program
        baseline = program.workout_routines
                          .where(week_number: program.current_week, day_number: today_dow)
                          .where(is_completed: false)
                          .includes(:routine_exercises)
                          .order(created_at: :desc)
                          .first

        if baseline.nil? || baseline.routine_exercises.blank?
          baseline = program.workout_routines
                            .where(week_number: program.current_week)
                            .where(is_completed: false)
                            .includes(:routine_exercises)
                            .order(Arel.sql("ABS(day_number - #{today_dow.to_i})"))
                            .detect { |r| r.routine_exercises.any? }
        end

        if baseline && baseline.routine_exercises.any?
          Rails.logger.info("[ChatService] Instant retrieval: baseline routine #{baseline.id} (week #{program.current_week}, day #{today_dow})")
          routine_data = format_existing_routine(baseline)
          routine_data = apply_routine_adjustments(routine_data)
          program_info = {
            name: program.name,
            current_week: program.current_week,
            total_weeks: program.total_weeks,
            phase: program.current_phase,
            volume_modifier: program.current_volume_modifier
          }
          return success_response(
            message: format_routine_message(routine_data, program_info),
            intent: "GENERATE_ROUTINE",
            data: { routine: routine_data, program: program_info, suggestions: [] }
          )
        end
      end

      Rails.logger.info("[ChatService] Calling ensure_training_program for user #{user.id}")
      program = ensure_training_program
      Rails.logger.info("[ChatService] Training program result: #{program&.id} - #{program&.name}")

      day_of_week = Time.current.wday
      day_of_week = day_of_week == 0 ? 7 : day_of_week

      recent_feedbacks = user.workout_feedbacks.order(created_at: :desc).limit(5)
      condition = parse_condition_string(input["condition"])

      routine = AiTrainer.generate_routine(
        user: user,
        day_of_week: day_of_week,
        condition_inputs: condition,
        recent_feedbacks: recent_feedbacks,
        goal: input["goal"]
      )

      if routine.is_a?(Hash) && routine[:success] == false
        return error_response(routine[:error] || "루틴 생성에 실패했어요.")
      end

      if routine.is_a?(Hash) && routine[:rest_day]
        Rails.logger.info("[ChatService] Rest day detected but user explicitly requested routine - retrying with goal")
        routine = AiTrainer.generate_routine(
          user: user,
          day_of_week: day_of_week,
          condition_inputs: condition,
          recent_feedbacks: recent_feedbacks,
          goal: "오늘 루틴 생성"
        )

        if routine.is_a?(Hash) && routine[:rest_day]
          return success_response(
            message: routine[:coach_message] || "오늘은 휴식일이에요! 충분한 회복을 취하세요 💤",
            intent: "REST_DAY",
            data: { rest_day: true, suggestions: [] }
          )
        end

        return error_response(routine[:error] || "루틴 생성에 실패했어요.") if routine.is_a?(Hash) && routine[:success] == false
      end

      program_info = if program
        {
          name: program.name,
          current_week: program.current_week,
          total_weeks: program.total_weeks,
          phase: program.current_phase,
          volume_modifier: program.current_volume_modifier
        }
      end

      routine = apply_routine_adjustments(routine)

      success_response(
        message: format_routine_message(routine, program_info),
        intent: "GENERATE_ROUTINE",
        data: { routine: routine, program: program_info, suggestions: [] }
      )
    end

    def ensure_training_program
      existing = user.active_training_program
      return existing if existing

      Rails.logger.info("[ChatService] User #{user.id} has no training program, generating one...")

      result = AiTrainer::ProgramGenerator.generate(user: user)

      if result[:success] && result[:program]
        Rails.logger.info("[ChatService] Created training program: #{result[:program].id} (#{result[:program].name})")
        result[:program]
      else
        Rails.logger.warn("[ChatService] Failed to generate training program: #{result[:error]}")
        nil
      end
    rescue StandardError => e
      Rails.logger.error("[ChatService] Error creating training program: #{e.message}")
      nil
    end

    def handle_replace_exercise(input)
      routine = current_routine
      return error_response("수정할 루틴을 찾을 수 없어요.") unless routine
      return error_response("이미 지난 루틴은 수정할 수 없어요.") unless routine_editable?(routine)

      rate_check = RoutineRateLimiter.check_and_increment!(user: user, action: :exercise_replacement)
      return error_response(rate_check[:error]) unless rate_check[:allowed]

      exercise = find_exercise_in_routine(routine, input["exercise_name"])
      return error_response("'#{input['exercise_name']}'을(를) 루틴에서 찾을 수 없어요.") unless exercise

      replacement = generate_exercise_replacement(
        routine: routine,
        old_exercise: exercise,
        reason: input["reason"]
      )
      return error_response(replacement[:error]) unless replacement[:success]

      old_name = exercise.exercise_name
      exercise.update!(
        exercise_name: replacement[:exercise_name],
        sets: replacement[:sets],
        reps: replacement[:reps],
        rest_duration_seconds: replacement[:rest_seconds] || 60,
        how_to: replacement[:instructions],
        weight_description: replacement[:weight_guide]
      )

      success_response(
        message: "#{old_name}을(를) **#{replacement[:exercise_name]}**(으)로 바꿨어요! 💪\n\n#{replacement[:reason]}",
        intent: "REPLACE_EXERCISE",
        data: {
          routine: routine.reload,
          new_exercise: exercise.reload,
          remaining_replacements: rate_check[:remaining],
          suggestions: []
        }
      )
    end

    def handle_add_exercise(input)
      routine = current_routine
      return error_response("운동을 추가할 루틴을 찾을 수 없어요.") unless routine
      return error_response("이미 지난 루틴은 수정할 수 없어요.") unless routine_editable?(routine)

      final_order = (routine.routine_exercises.maximum(:order_index) || -1) + 1
      normalized_name = AiTrainer::ExerciseNameNormalizer.normalize_if_needed(input["exercise_name"])

      exercise = routine.routine_exercises.create!(
        exercise_name: normalized_name,
        order_index: final_order,
        sets: input["sets"] || 3,
        reps: input["reps"] || 10,
        target_muscle: infer_target_muscle(input["exercise_name"]),
        rest_duration_seconds: 60
      )

      success_response(
        message: "**#{normalized_name}** #{exercise.sets}세트 x #{exercise.reps}회를 추가했어요! 💪",
        intent: "ADD_EXERCISE",
        data: {
          routine: routine.reload,
          added_exercise: exercise,
          suggestions: []
        }
      )
    end

    def handle_delete_exercise(input)
      routine = current_routine
      return error_response("수정할 루틴을 찾을 수 없어요.") unless routine
      return error_response("이미 지난 루틴은 수정할 수 없어요.") unless routine_editable?(routine)

      exercise_name = input["exercise_name"]
      return error_response("삭제할 운동 이름을 알려주세요.") if exercise_name.blank?

      exercise = routine.routine_exercises.find_by("exercise_name ILIKE ?", "%#{exercise_name}%")
      return error_response("'#{exercise_name}' 운동을 찾을 수 없어요.") unless exercise

      deleted_name = exercise.exercise_name
      exercise.destroy!

      routine.routine_exercises.order(:order_index).each_with_index do |ex, idx|
        ex.update!(order_index: idx)
      end

      routine_data = format_existing_routine(routine.reload)

      success_response(
        message: "**#{deleted_name}**을(를) 루틴에서 삭제했어요! ✂️",
        intent: "DELETE_EXERCISE",
        data: {
          routine: routine_data,
          deleted_exercise: deleted_name,
          suggestions: []
        }
      )
    end

    def generate_exercise_replacement(routine:, old_exercise:, reason:)
      other_exercises = routine.routine_exercises
                               .where.not(id: old_exercise.id)
                               .pluck(:exercise_name)

      tier = AiTrainer::Constants.tier_for_level(user.user_profile&.numeric_level || 1)

      prompt = <<~PROMPT
        ## 교체할 운동
        - 운동명: #{old_exercise.exercise_name}
        - 타겟 근육: #{old_exercise.target_muscle}
        - 세트: #{old_exercise.sets}, 횟수: #{old_exercise.reps}

        ## 교체 이유
        #{reason || "다른 운동으로 변경 원함"}

        ## 조건
        - 사용자 레벨: #{tier}
        - 피해야 할 운동: #{other_exercises.join(', ')}

        JSON으로 대체 운동을 추천해주세요.
      PROMPT

      system = <<~SYSTEM
        전문 피트니스 트레이너입니다. JSON 형식으로만 응답하세요:
        {"exercise_name": "운동명", "sets": 3, "reps": 10, "rest_seconds": 60, "instructions": "방법", "weight_guide": "무게", "reason": "추천 이유"}
      SYSTEM

      response = AiTrainer::LlmGateway.chat(prompt: prompt, task: :exercise_replacement, system: system)
      return { success: false, error: "AI 응답 실패" } unless response[:success]

      raw_json = if response[:content] =~ /```(?:json)?\s*(\{.*?\})\s*```/m
        Regexp.last_match(1)
      elsif response[:content].include?("{")
        start_idx = response[:content].index("{")
        end_idx   = response[:content].rindex("}")
        response[:content][start_idx..end_idx]
      else
        response[:content]
      end

      data = JSON.parse(raw_json)
      normalized_name = AiTrainer::ExerciseNameNormalizer.normalize_if_needed(data["exercise_name"])
      {
        success: true,
        exercise_name: normalized_name,
        sets: data["sets"] || 3,
        reps: data["reps"] || 10,
        rest_seconds: data["rest_seconds"] || 60,
        instructions: data["instructions"],
        weight_guide: data["weight_guide"],
        reason: data["reason"]
      }
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse replacement JSON: #{e.message}")
      { success: false, error: "응답 파싱 실패" }
    end
  end
end
