# frozen_string_literal: true

# Extracted from ChatService: tool dispatch + all handle_* methods,
# condition helpers, exercise replacement, and workout completion.
module ChatToolHandlers
  extend ActiveSupport::Concern

  private

  def execute_tool(tool_use)
    tool_name = tool_use[:name]
    input = tool_use[:input] || {}

    Rails.logger.info("[ChatService] Executing tool: #{tool_name} with input: #{input}")

    case tool_name
    when "generate_routine"
      handle_generate_routine(input)
    when "check_condition"
      handle_check_condition(input)
    when "record_exercise"
      handle_record_exercise(input)
    when "replace_exercise"
      handle_replace_exercise(input)
    when "add_exercise"
      handle_add_exercise(input)
    when "delete_exercise"
      handle_delete_exercise(input)
    when "explain_long_term_plan"
      handle_explain_long_term_plan(input)
    when "complete_workout"
      handle_complete_workout(input)
    when "submit_feedback"
      handle_submit_feedback(input)
    else
      error_response("알 수 없는 작업입니다: #{tool_name}")
    end
  end

  # ============================================
  # Tool Handlers
  # ============================================

  def handle_generate_routine(input)
    profile = user.user_profile

    # Check if user has completed onboarding (either method)
    unless profile&.onboarding_completed_at.present? || profile&.numeric_level.present?
      # Try to guide them through onboarding first
      if AiTrainer::LevelAssessmentService.needs_assessment?(user)
        return error_response("먼저 간단한 상담을 완료해주세요! 그래야 맞춤 루틴을 만들 수 있어요. 💬")
      else
        return error_response("프로필 설정이 완료되지 않았어요. 상담을 먼저 진행해주세요!")
      end
    end

    # Ensure numeric_level is set (fallback to 1 if missing)
    unless profile.numeric_level.present?
      Rails.logger.warn("[ChatService] User #{user.id} has onboarding completed but no numeric_level, setting default")
      profile.update!(numeric_level: 1, current_level: "beginner")
    end

    # Check for today's existing incomplete routine
    today_routine = WorkoutRoutine.where(user_id: user.id)
                                  .where("created_at >= ?", Time.current.beginning_of_day)
                                  .where(is_completed: false)
                                  .order(created_at: :desc)
                                  .first

    if today_routine
      # Return existing routine instead of creating a new one
      routine_data = format_existing_routine(today_routine)
      return success_response(
        message: "오늘의 루틴이에요! 💪\n\n특정 운동을 바꾸고 싶으면 'XX 대신 다른 운동'이라고 말씀해주세요.",
        intent: "GENERATE_ROUTINE",
        data: { routine: routine_data, suggestions: ["운동 끝났어", "운동 하나 교체해줘"] }
      )
    end

    # Ensure user has a training program (create if missing)
    Rails.logger.info("[ChatService] Calling ensure_training_program for user #{user.id}")
    program = ensure_training_program
    Rails.logger.info("[ChatService] Training program result: #{program&.id} - #{program&.name}")

    day_of_week = Time.current.wday
    day_of_week = day_of_week == 0 ? 7 : day_of_week

    recent_feedbacks = user.workout_feedbacks.order(created_at: :desc).limit(5)

    # LLM이 파악한 컨디션 문자열을 해시로 변환
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

    # Rest day: return rest message without generating routine
    if routine.is_a?(Hash) && routine[:rest_day]
      return success_response(
        message: routine[:coach_message] || "오늘은 휴식일이에요! 충분한 회복을 취하세요 💤",
        intent: "REST_DAY",
        data: { rest_day: true, suggestions: ["내일 루틴 알려줘", "그래도 오늘 운동하고 싶어"] }
      )
    end

    # Add program context to response if available
    program_info = if program
      {
        name: program.name,
        current_week: program.current_week,
        total_weeks: program.total_weeks,
        phase: program.current_phase,
        volume_modifier: program.current_volume_modifier
      }
    end

    success_response(
      message: format_routine_message(routine, program_info),
      intent: "GENERATE_ROUTINE",
      data: { routine: routine, program: program_info, suggestions: ["운동 끝났어", "운동 하나 교체해줘"] }
    )
  end

  # Ensure user has a training program, create one if missing
  def ensure_training_program
    # Check if user already has an active program
    existing = user.active_training_program
    return existing if existing

    Rails.logger.info("[ChatService] User #{user.id} has no training program, generating one...")

    # Generate program using ProgramGenerator
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

  def handle_check_condition(input)
    condition_text = input["condition_text"]
    return error_response("컨디션 상태를 알려주세요.") if condition_text.blank?

    # Use ConditionService to analyze and save condition
    result = AiTrainer::ConditionService.analyze_from_voice(
      user: user,
      text: condition_text
    )

    unless result[:success]
      return error_response(result[:error] || "컨디션 분석에 실패했어요.")
    end

    # Save condition log
    condition = result[:condition]
    save_condition_log_from_result(condition)

    # Check if user already has today's routine
    today_routine = WorkoutRoutine.where(user_id: user.id)
                                   .where("created_at >= ?", Time.current.beginning_of_day)
                                   .first

    if today_routine
      # Already has today's routine - just acknowledge condition
      message = build_condition_response_message(condition, result)
      message += "\n\n오늘 루틴이 이미 있어요! 컨디션을 반영해서 진행해주세요 💪"

      return success_response(
        message: message,
        intent: "CHECK_CONDITION",
        data: {
          condition: condition,
          intensity_modifier: result[:intensity_modifier],
          existing_routine_id: today_routine.id,
          suggestions: ["루틴 보여줘", "운동 시작할게"]
        }
      )
    end

    # No today's routine - generate one with condition
    routine_result = AiTrainer.generate_routine(
      user: user,
      day_of_week: Time.current.wday == 0 ? 7 : Time.current.wday,
      condition_inputs: { text: condition_text, analyzed: condition },
      recent_feedbacks: user.workout_feedbacks.order(created_at: :desc).limit(5)
    )

    if routine_result.is_a?(Hash) && routine_result[:success] == false
      # Routine generation failed - just return condition response
      message = build_condition_response_message(condition, result)
      return success_response(
        message: message,
        intent: "CHECK_CONDITION",
        data: {
          condition: condition,
          suggestions: ["오늘 루틴 만들어줘", "좀 더 쉬울래"]
        }
      )
    end

    # Rest day: return condition + rest message
    if routine_result.is_a?(Hash) && routine_result[:rest_day]
      message = build_condition_response_message(condition, result)
      message += "\n\n오늘은 프로그램에 따른 휴식일이에요! 충분한 회복을 취하세요 💤"
      return success_response(
        message: message,
        intent: "REST_DAY",
        data: { rest_day: true, condition: condition, suggestions: ["그래도 오늘 운동하고 싶어", "내일 루틴 알려줘"] }
      )
    end

    # Build combined response: condition + routine
    condition_msg = build_condition_acknowledgment(condition)
    routine_msg = format_routine_for_display(routine_result)

    success_response(
      message: "#{condition_msg}\n\n#{routine_msg}",
      intent: "CONDITION_AND_ROUTINE",
      data: {
        condition: condition,
        intensity_modifier: result[:intensity_modifier],
        routine: routine_result,
        suggestions: ["운동 시작!", "운동 하나 교체해줘", "운동 끝났어"]
      }
    )
  end

  def build_condition_acknowledgment(condition)
    messages = {
      "good" => "컨디션 좋으시네요! 💪 오늘 강도 높여서 진행할게요!",
      "normal" => "알겠어요! 👍 평소 강도로 진행할게요.",
      "tired" => "피곤하시군요 😊 오늘은 가볍게 진행할게요!",
      "injured" => "아프신 부위가 있군요 🤕 해당 부위는 피해서 진행할게요."
    }
    messages[condition.to_s] || "컨디션 확인했어요! 👍"
  end

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
        data: {
          records: [ record_item ],
          suggestions: ["다음 운동 기록", "운동 끝났어", "오늘 총 기록 보기"]
        }
      )
    else
      error_response(result[:error] || "기록 저장에 실패했어요.")
    end
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
        suggestions: ["운동 시작할게!", "다른 것도 바꿔줘", "운동 끝났어"]
      }
    )
  end

  def handle_add_exercise(input)
    routine = current_routine
    return error_response("운동을 추가할 루틴을 찾을 수 없어요.") unless routine
    return error_response("이미 지난 루틴은 수정할 수 없어요.") unless routine_editable?(routine)

    final_order = (routine.routine_exercises.maximum(:order_index) || -1) + 1
    # Normalize exercise name to Korean
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
        suggestions: ["운동 시작!", "다른 운동도 추가해줘", "운동 끝났어"]
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

    # Reorder remaining exercises
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
        suggestions: ["운동 시작!", "다른 운동 추가해줘", "운동 끝났어"]
      }
    )
  end

  def handle_explain_long_term_plan(input)
    profile = user.user_profile

    unless profile&.onboarding_completed_at
      return error_response("먼저 상담을 완료해주세요. 그래야 맞춤 운동 계획을 세울 수 있어요!")
    end

    # Get consultation data
    consultation_data = profile.fitness_factors&.dig("collected_data") || {}

    # Build long-term plan
    long_term_plan = build_long_term_plan(profile, consultation_data)

    # Enrich with actual TrainingProgram data
    program = user.active_training_program
    if program
      long_term_plan[:current_week] = program.current_week
      long_term_plan[:total_weeks] = program.total_weeks
      long_term_plan[:current_phase] = program.current_phase
      long_term_plan[:program_name] = program.name
      long_term_plan[:progress_percentage] = program.progress_percentage
    end

    detail_level = input["detail_level"] || "detailed"

    # Generate AI explanation
    prompt = <<~PROMPT
      사용자의 장기 운동 계획을 #{detail_level == 'brief' ? '간단히' : '자세히'} 설명해주세요.

      ## 사용자 정보
      - 이름: #{user.name || '회원'}
      - 레벨: #{profile.numeric_level || 1} (#{tier_korean(profile.tier || 'beginner')})
      - 목표: #{profile.fitness_goal || '건강'}
      - 운동 빈도: #{consultation_data['frequency'] || '주 3회'}
      - 운동 환경: #{consultation_data['environment'] || '헬스장'}
      - 부상/주의사항: #{consultation_data['injuries'] || '없음'}
      - 집중 부위: #{consultation_data['focus_areas'] || '전체'}

      ## 주간 스플릿
      #{long_term_plan[:weekly_split]}

      ## 훈련 전략
      #{long_term_plan[:description]}

      ## 점진적 과부하 전략
      #{long_term_plan[:progression_strategy]}

      ## 예상 타임라인
      #{long_term_plan[:estimated_timeline]}

      ## 현재 진행 상황
      - 프로그램: #{long_term_plan[:program_name] || '미설정'}
      - 현재 주차: #{long_term_plan[:current_week] || '?'}/#{long_term_plan[:total_weeks] || '?'}주
      - 현재 페이즈: #{long_term_plan[:current_phase] || '미설정'}
      - 진행률: #{long_term_plan[:progress_percentage] || 0}%

      ## 응답 규칙
      1. 사용자 정보 기반 맞춤 계획 설명
      2. 주간 스케줄 구체적으로 안내 (요일별 운동 부위)
      3. 목표 달성을 위한 전략 설명
      4. 점진적 과부하 방법 안내
      5. 예상 결과 시점 안내
      6. 친근하고 격려하는 톤
      7. 이모지 적절히 사용
    PROMPT

    response = AiTrainer::LlmGateway.chat(
      prompt: prompt,
      task: :explain_plan,
      system: "당신은 친근하면서도 전문적인 피트니스 AI 트레이너입니다. 한국어로 응답하세요."
    )

    message = if response[:success]
      response[:content]
    else
      format_long_term_plan_message(long_term_plan, profile)
    end

    success_response(
      message: message,
      intent: "EXPLAIN_LONG_TERM_PLAN",
      data: {
        long_term_plan: long_term_plan,
        user_profile: {
          level: profile.numeric_level || 1,
          tier: profile.tier || "beginner",
          goal: profile.fitness_goal
        },
        suggestions: [
          "오늘 루틴 만들어줘",
          "내일은 뭐 해야 해?",
          "휴식일에는 뭐 하면 좋아?"
        ]
      }
    )
  end

  def handle_submit_feedback(input)
    feedback_text = input["feedback_text"]
    feedback_type = input["feedback_type"]&.to_sym || :specific

    return error_response("피드백 내용을 알려주세요.") if feedback_text.blank?

    # Store feedback
    store_workout_feedback(feedback_type, feedback_text)

    # Generate response based on feedback type
    responses = {
      just_right: {
        message: "좋아요! 👍 현재 강도가 딱 맞는 것 같네요.\n\n다음 운동에도 비슷한 강도로 진행할게요. 꾸준히 하시면 2주 후에는 자연스럽게 강도를 올릴 수 있을 거예요! 💪",
        adjustment: 0
      },
      too_easy: {
        message: "알겠어요! 💪 다음 운동부터 **강도를 올릴게요**.\n\n세트 수나 중량을 조금씩 늘려서 더 도전적인 루틴을 만들어드릴게요!",
        adjustment: 0.1
      },
      too_hard: {
        message: "알겠어요! 😊 다음 운동은 **강도를 낮춰서** 진행할게요.\n\n무리하지 않는 게 중요해요. 폼을 잘 유지하면서 점진적으로 늘려가요!",
        adjustment: -0.1
      },
      specific: {
        message: "피드백 감사합니다! 🙏\n\n\"#{feedback_text}\" - 다음 루틴에 반영할게요!",
        adjustment: 0
      }
    }

    response_data = responses[feedback_type] || responses[:specific]

    lines = []
    lines << response_data[:message]
    lines << ""
    lines << "---"
    lines << ""
    lines << "내일 또 운동하러 오세요! 채팅창에 들어오시면 오늘의 루틴을 준비해드릴게요 🔥"

    success_response(
      message: lines.join("\n"),
      intent: "FEEDBACK_RECEIVED",
      data: {
        feedback_type: feedback_type.to_s,
        feedback_text: feedback_text,
        intensity_adjustment: response_data[:adjustment],
        suggestions: ["이번 주 기록 보기", "프로그램 진행 상황"]
      }
    )
  end

  def store_workout_feedback(feedback_type, feedback_text = nil)
    profile = user.user_profile
    return unless profile

    feedback_type_sym = feedback_type.to_s.to_sym
    factors = profile.fitness_factors || {}

    # Store feedback history
    feedbacks = factors["workout_feedbacks"] || []
    feedbacks << {
      date: Date.current.to_s,
      type: feedback_type_sym.to_s,
      text: feedback_text,
      recorded_at: Time.current.iso8601
    }

    # Keep last 30 feedbacks
    feedbacks = feedbacks.last(30)

    # Calculate running intensity adjustment
    adjustment = factors["intensity_adjustment"] || 0.0
    case feedback_type_sym
    when :too_easy
      adjustment = [adjustment + 0.05, 0.3].min  # Max +30%
    when :too_hard
      adjustment = [adjustment - 0.05, -0.3].max  # Max -30%
    end

    factors["workout_feedbacks"] = feedbacks
    factors["intensity_adjustment"] = adjustment
    factors["last_feedback_at"] = Time.current.iso8601

    profile.update!(fitness_factors: factors)
  end

  def handle_complete_workout(input)
    # Get today's routine
    today_routine = WorkoutRoutine.where(user_id: user.id)
                                   .where("created_at > ?", Time.current.beginning_of_day)
                                   .order(created_at: :desc)
                                   .first

    # End active workout session and collect stats
    active_session = user.workout_sessions.where(end_time: nil).order(created_at: :desc).first
    completed_sets = 0
    total_volume = 0
    exercises_count = 0

    if active_session
      completed_sets = active_session.total_sets
      total_volume = active_session.total_volume
      exercises_count = active_session.exercises_performed
      active_session.complete!
    end

    # Complete the routine
    today_routine&.complete! unless today_routine&.is_completed

    # Mark workout as completed for feedback tracking
    mark_workout_completed

    # Save notes if provided
    notes = input["notes"]
    if notes.present? && today_routine
      today_routine.update(notes: notes)
    end

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
        suggestions: ["적당했어", "좀 쉬웠어", "힘들었어", "스쿼트가 어려웠어"]
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

  def store_today_condition(condition, intensity)
    profile = user.user_profile
    return unless profile

    today = Time.current.to_date.to_s

    # Store in fitness_factors
    factors = profile.fitness_factors || {}
    factors["daily_conditions"] ||= {}
    factors["daily_conditions"][today] = {
      condition: condition.to_s,
      intensity: intensity,
      recorded_at: Time.current.iso8601
    }

    profile.update!(fitness_factors: factors)
  end

  def generate_routine_with_condition(condition, intensity)
    condition_messages = {
      good: "컨디션 좋으시네요! 💪 오늘은 **강도 110%**로 진행할게요!",
      normal: "알겠어요! 오늘은 **평소 강도**로 진행할게요 👍",
      tired: "피곤하시군요 😊 오늘은 **강도 70%**로 가볍게 진행할게요!"
    }

    intro = condition_messages[condition]

    # Get today's suggested workout (based on split/schedule)
    suggested_focus = suggest_today_focus

    # Acknowledge condition and suggest workout
    success_response(
      message: "#{intro}\n\n오늘은 어떤 운동을 하고 싶으세요?\n\n🏋️ 추천 부위: **#{suggested_focus[:focus]}**\n⏱️ 예상 시간: #{suggested_focus[:duration]}분\n\n\"#{suggested_focus[:focus]} 운동 해줘\" 라고 말씀해주세요!",
      intent: "CONDITION_ACKNOWLEDGED",
      data: {
        condition: condition.to_s,
        intensity: intensity,
        suggested_focus: suggested_focus[:focus],
        suggestions: [
          "#{suggested_focus[:focus]} 운동 해줘",
          "가슴 운동 할래",
          "하체 운동 해줘"
        ]
      }
    )
  end

  def suggest_today_focus
    today = Time.current
    day_of_week = today.wday  # 0=일, 1=월, ...

    # Check user's recent workouts to suggest next focus
    recent_sessions = user.workout_sessions
                          .where("start_time > ?", 7.days.ago)
                          .order(start_time: :desc)
                          .limit(7)

    recent_focuses = recent_sessions.map(&:name).compact

    # Default 3-split rotation
    default_split = {
      1 => { focus: "가슴/삼두", duration: 60 },  # 월
      2 => { focus: "등/이두", duration: 60 },    # 화
      3 => { focus: "하체", duration: 60 },       # 수
      4 => { focus: "어깨", duration: 50 },       # 목
      5 => { focus: "가슴/등", duration: 60 },    # 금
      6 => { focus: "하체/코어", duration: 50 },  # 토
      0 => { focus: "휴식 또는 유산소", duration: 30 }  # 일
    }

    # If user did this focus recently, suggest alternative
    suggested = default_split[day_of_week]

    if recent_focuses.include?(suggested[:focus])
      # Find least recently done
      all_focuses = ["가슴", "등", "하체", "어깨", "팔"]
      least_recent = all_focuses.find { |f| !recent_focuses.any? { |r| r.include?(f) } }
      suggested = { focus: least_recent || "전신", duration: 60 }
    end

    suggested
  end

  # LLM이 전달한 컨디션 문자열을 해시로 변환
  def parse_condition_string(condition_str)
    return nil if condition_str.blank?

    { notes: condition_str }
  end

  # Save condition log from check_condition result
  def save_condition_log_from_result(condition)
    return unless condition

    user.condition_logs.create!(
      date: Date.current,
      energy_level: condition[:energy_level] || 3,
      stress_level: condition[:stress_level] || 3,
      sleep_quality: condition[:sleep_quality] || 3,
      motivation: condition[:motivation] || 3,
      soreness: condition[:soreness] || {},
      available_time: condition[:available_time] || 60,
      notes: "Chat에서 입력"
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("ChatService: Failed to save condition log: #{e.message}")
  end

  # Build user-friendly response message for condition check
  def build_condition_response_message(condition, result)
    energy = condition[:energy_level] || 3
    stress = condition[:stress_level] || 3
    motivation = condition[:motivation] || 3

    # Determine overall condition status
    avg_score = (energy + (6 - stress) + motivation) / 3.0

    status_emoji, status_text = if avg_score >= 4
      [ "💪", "좋은 컨디션" ]
    elsif avg_score >= 3
      [ "👍", "괜찮은 컨디션" ]
    elsif avg_score >= 2
      [ "😊", "조금 피곤한 컨디션" ]
    else
      [ "🌙", "휴식이 필요한 컨디션" ]
    end

    msg = "#{status_emoji} 오늘 #{status_text}이시네요! 컨디션을 기록했어요.\n\n"

    # Add interpretation if available
    if result[:interpretation].present?
      msg += "#{result[:interpretation]}\n\n"
    end

    # Add adaptations as suggestions
    if result[:adaptations].present? && result[:adaptations].any?
      msg += "📝 **운동 시 참고하세요:**\n"
      result[:adaptations].first(3).each do |adaptation|
        msg += "• #{adaptation}\n"
      end
      msg += "\n"
    end

    # Add suggestions based on condition
    suggestions = build_condition_suggestions(condition, result)
    if suggestions.any?
      msg += "오늘 어떤 운동을 해볼까요? 루틴이 필요하면 말씀해주세요!"
    end

    msg
  end

  def build_condition_suggestions(condition, result)
    suggestions = []
    energy = condition[:energy_level] || 3
    intensity = result[:intensity_modifier] || 1.0

    if energy <= 2 || intensity < 0.8
      suggestions << "가벼운 루틴 만들어줘"
      suggestions << "스트레칭만 할래"
    elsif energy >= 4
      suggestions << "오늘 루틴 만들어줘"
      suggestions << "강하게 운동하고 싶어"
    else
      suggestions << "오늘 루틴 만들어줘"
    end

    suggestions
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

    data = JSON.parse(extract_json(response[:content]))
    # Normalize exercise name to Korean
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

  def infer_target_muscle(exercise_name)
    name_lower = exercise_name.downcase

    mappings = {
      "chest" => %w[벤치 푸시업 체스트 플라이 딥스],
      "back" => %w[풀업 로우 렛풀 데드리프트 턱걸이],
      "shoulders" => %w[숄더 프레스 레이즈 어깨],
      "legs" => %w[스쿼트 런지 레그 프레스 컬 익스텐션],
      "arms" => %w[컬 바이셉 트라이셉 삼두 이두],
      "core" => %w[플랭크 크런치 싯업 복근 코어]
    }

    mappings.each do |muscle, keywords|
      return muscle if keywords.any? { |kw| name_lower.include?(kw) }
    end

    "other"
  end

  # General Chat with RAG
  def handle_general_chat_with_rag
    result = AiTrainer::ChatService.general_chat(
      user: user,
      message: message,
      session_id: session_id
    )

    # Cache the response for future identical questions
    answer = result[:message] || "무엇을 도와드릴까요?"
    cache_response(answer)

    answer_msg = result[:message] || "무엇을 도와드릴까요?"
    suggestions = extract_suggestions_from_message(answer_msg)
    clean_msg = strip_suggestions_text(answer_msg)

    success_response(
      message: clean_msg,
      intent: "GENERAL_CHAT",
      data: {
        knowledge_used: result[:knowledge_used],
        session_id: result[:session_id],
        suggestions: suggestions.presence || [
          "오늘 루틴 만들어줘",
          "내 운동 계획 알려줘",
          "더 궁금한 거 있어"
        ]
      }
    )
  end
end
