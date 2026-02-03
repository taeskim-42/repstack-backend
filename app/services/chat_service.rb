# frozen_string_literal: true

# ChatService: Tool Use based AI trainer
# LLM decides which tool to use based on user message
class ChatService
  class << self
    def process(user:, message:, routine_id: nil, session_id: nil)
      new(user: user, message: message, routine_id: routine_id, session_id: session_id).process
    end
  end

  def initialize(user:, message:, routine_id: nil, session_id: nil)
    @user = user
    @message = message.strip
    @routine_id = routine_id
    @session_id = session_id
  end

  def process
    # Reload user to get fresh profile data
    user.reload
    
    # 0. Daily greeting (AI first - for all users when entering chat)
    if needs_daily_greeting?
      return handle_daily_greeting
    end

    # 0.5. "Show today's routine" response (after program creation) - MUST be before condition_response
    # Because "네", "1" can match both patterns, but if no routines exist, this takes priority
    if wants_today_routine?
      return handle_show_today_routine
    end

    # 1. Welcome message for newly onboarded users
    if needs_welcome_message?
      return handle_welcome_message
    end

    # 2. New user onboarding (special flow - not tool-based)
    if needs_level_assessment?
      return handle_level_assessment
    end

    # 3. Tool Use based processing
    process_with_tools
  rescue StandardError => e
    Rails.logger.error("ChatService error: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
    error_response("처리 중 오류가 발생했습니다: #{e.message}")
  end

  private

  attr_reader :user, :message, :routine_id, :session_id

  # ============================================
  # Semantic Response Cache (Vector Similarity)
  # ============================================

  def get_cached_response
    return nil if message.blank? || message.length < 10

    # Try to find semantically similar cached response
    cached = ChatResponseCache.find_similar(message)
    return cached.answer if cached

    nil
  rescue => e
    Rails.logger.error("[ChatService] Cache lookup error: #{e.message}")
    nil
  end

  def cache_response(answer)
    return if answer.blank? || message.blank? || message.length < 10

    # Cache in background to not block response
    Thread.new do
      ChatResponseCache.cache_response(question: message, answer: answer)
    rescue => e
      Rails.logger.error("[ChatService] Cache save error: #{e.message}")
    end
  end

  # ============================================
  # Tool Use Processing
  # ============================================

  def process_with_tools
    # Check cache first (skip LLM if cached)
    cached_answer = get_cached_response
    if cached_answer
      return success_response(
        message: cached_answer,
        intent: "CACHED_RESPONSE",
        data: { cached: true }
      )
    end

    Rails.logger.info("[ChatService] Processing message: #{message}")
    Rails.logger.info("[ChatService] Available tools: #{available_tools.map { |t| t[:name] }.join(', ')}")

    # Build conversation history for context
    conversation_messages = build_conversation_history

    response = AiTrainer::LlmGateway.chat(
      prompt: build_user_prompt,
      task: :general_chat,
      system: system_prompt,
      messages: conversation_messages,
      tools: available_tools
    )

    Rails.logger.info("[ChatService] LLM response success: #{response[:success]}, tool_use: #{response[:tool_use].present?}")

    return error_response("AI 응답 실패") unless response[:success]

    # Check if LLM called a tool
    if response[:tool_use]
      Rails.logger.info("[ChatService] Tool called: #{response[:tool_use][:name]}")
      execute_tool(response[:tool_use])
    else
      Rails.logger.info("[ChatService] No tool called, using RAG for general chat")
      handle_general_chat_with_rag
    end
  end

  def build_user_prompt
    prompt = message

    # Add routine context if available
    if routine_id.present? && current_routine
      exercises = current_routine.routine_exercises.order(:order_index).map do |ex|
        "#{ex.order_index + 1}. #{ex.exercise_name} (#{ex.sets}세트 x #{ex.reps}회)"
      end.join("\n")

      prompt = <<~PROMPT
        [현재 루틴]
        #{exercises}

        [사용자 메시지]
        #{message}
      PROMPT
    end

    prompt
  end

  def system_prompt
    tier = user.user_profile&.tier || "beginner"
    level = user.user_profile&.level || 1
    today = Time.current.in_time_zone("Asia/Seoul")
    day_names = %w[일 월 화 수 목 금 토]

    # Check if user has today's routine (for feedback vs condition distinction)
    has_today_routine = WorkoutRoutine.where(user_id: user.id)
                                       .where("created_at >= ?", Time.current.beginning_of_day)
                                       .exists?

    # Check if workout was recently completed
    workout_completed = user.user_profile&.fitness_factors&.dig("last_workout_completed_at").present? &&
                        Time.parse(user.user_profile.fitness_factors["last_workout_completed_at"]) > Time.current.beginning_of_day rescue false

    <<~SYSTEM
      당신은 전문 피트니스 AI 트레이너입니다.

      ## 현재 시간
      - 오늘: #{today.strftime('%Y년 %m월 %d일')} (#{day_names[today.wday]}요일)
      - 시간: #{today.strftime('%H:%M')}

      ## 사용자 정보
      - 레벨: #{level} (#{tier_korean(tier)})
      - 이름: #{user.name || '회원'}
      - 오늘 루틴 있음: #{has_today_routine ? '예' : '아니오'}
      - 오늘 운동 완료: #{workout_completed ? '예' : '아니오'}

      ## 대화 맥락
      #{conversation_context_summary}

      ## 중요: Tool 사용 규칙
      다음 요청에는 **반드시** 해당 tool을 호출하세요. 텍스트로 직접 답변하지 마세요:

      1. 루틴/운동 프로그램 요청 → **generate_routine** tool 필수
         예: "루틴 만들어줘", "오늘 운동 뭐해", "등운동 루틴", "광배근 루틴"
         (컨디션 + 루틴 요청: "피곤한데 운동 뭐해" → generate_routine의 condition 파라미터 사용)

      2. 컨디션만 언급 (루틴 요청 없이) → **check_condition** tool 필수
         예: "피곤해", "오늘 컨디션 안좋아", "어깨가 아파"
         ※ 오늘 루틴이 없거나, 운동 시작 전 상태를 말할 때만 사용

      3. 운동 기록 요청 → **record_exercise** tool 필수
         예: "벤치프레스 60kg 8회", "스쿼트 10회 했어"

      4. 운동 교체 요청 → **replace_exercise** tool 필수 (routineId가 있을 때)
         예: "XX 말고 다른거", "XX 대신 다른 운동", "이거 힘들어", "XX 빼줘"

      5. 운동 추가 요청 → **add_exercise** tool 필수 (routineId가 있을 때)
         예: "XX도 넣어줘", "팔운동 더 하고싶어"

      6. 루틴 전체 재생성 → **regenerate_routine** tool 필수 (routineId가 있을 때)
         예: "다른 루틴으로", "전부 바꿔줘", "마음에 안들어"

      7. 운동 계획/프로그램 설명 요청 → **explain_long_term_plan** tool 필수
         예: "내 운동 계획 알려줘", "주간 스케줄", "어떻게 운동해야 해", "프로그램 설명해줘", "나 어떤 운동 하면 돼"

      8. 운동 완료 선언 → **complete_workout** tool 필수
         예: "운동 끝났어", "완료", "다 했어", "끝", "오늘 운동 끝", "done", "finished"

      9. 운동 피드백 제출 → **submit_feedback** tool 필수
         예: "적당했어", "힘들었어", "스쿼트가 어려웠어"
         ※ feedback_type: just_right(적당/긍정), too_easy(쉬움), too_hard(힘듦), specific(특정 운동)
         ※ 판단 기준: 오늘 루틴 있음 + 운동 완료됨 상태에서 짧은 반응은 피드백으로 처리

      ## Tool 선택 판단 기준
      - **오늘 루틴 있음 + 운동 완료됨** 상태에서 짧은 반응 → submit_feedback (피드백)
      - **오늘 루틴 없음** 또는 **운동 시작 전** 컨디션 언급 → check_condition (컨디션)
      - 대화 맥락을 보고 사용자의 의도를 파악하세요

      ## 일반 대화만 tool 없이 답변
      - 운동 지식 질문, 폼 체크 설명, 일반 인사 등
      - 단, "XX 말고", "XX 대신" 등 교체 요청은 반드시 replace_exercise 호출!

      ## 응답 스타일
      - 친근하고 격려하는 톤
      - 한국어로 응답
    SYSTEM
  end

  def available_tools
    tools = [
      {
        name: "generate_routine",
        description: "새로운 운동 루틴을 생성합니다. 사용자가 '루틴 줘', '오늘 운동 뭐해', '피곤한데 운동 뭐해' 등 루틴을 요청할 때 사용합니다.",
        input_schema: {
          type: "object",
          properties: {
            goal: {
              type: "string",
              description: "운동 목표 (예: 가슴, 등, 체중감량)"
            },
            condition: {
              type: "string",
              description: "사용자 컨디션 그대로 전달 (예: '피곤함', '어깨가 좀 아파', '컨디션 좋음')"
            }
          },
          required: []
        }
      },
      {
        name: "check_condition",
        description: "사용자의 컨디션을 파악하고 기록합니다. 사용자가 '피곤해', '컨디션 안좋아', '오늘 좀 힘들어', '잠을 못잤어', '어깨가 아파', '컨디션 좋아', '굿', '최고' 등 자신의 상태를 말할 때 사용합니다. 루틴 요청 없이 컨디션만 언급할 때 이 tool을 호출하세요.",
        input_schema: {
          type: "object",
          properties: {
            condition_text: {
              type: "string",
              description: "사용자가 말한 컨디션 상태 원문 (예: '피곤해', '어깨가 좀 아파', '굿')"
            }
          },
          required: %w[condition_text]
        }
      },
      {
        name: "record_exercise",
        description: "운동 기록을 저장합니다. 사용자가 '벤치프레스 60kg 8회', '스쿼트 10회 3세트 했어' 등 운동 수행 내용을 말할 때 사용합니다.",
        input_schema: {
          type: "object",
          properties: {
            exercise_name: {
              type: "string",
              description: "운동 이름 (예: 벤치프레스, 스쿼트)"
            },
            weight: {
              type: "number",
              description: "무게 (kg). 맨몸 운동이면 생략"
            },
            reps: {
              type: "integer",
              description: "반복 횟수"
            },
            sets: {
              type: "integer",
              description: "세트 수 (기본값: 1)"
            }
          },
          required: %w[exercise_name reps]
        }
      },
      {
        name: "explain_long_term_plan",
        description: "사용자의 장기 운동 계획을 설명합니다. '내 운동 계획 알려줘', '주간 스케줄', '어떻게 운동해야 해', '프로그램 설명해줘' 등의 요청에 사용합니다.",
        input_schema: {
          type: "object",
          properties: {
            detail_level: {
              type: "string",
              description: "설명 수준 (brief: 간단히, detailed: 자세히)"
            }
          },
          required: []
        }
      },
      {
        name: "complete_workout",
        description: "사용자가 오늘 운동을 완료했음을 기록합니다. '운동 끝났어', '완료', '다 했어', '끝', 'done', '오늘 운동 끝' 등의 요청에 사용합니다.",
        input_schema: {
          type: "object",
          properties: {
            notes: {
              type: "string",
              description: "운동에 대한 메모나 코멘트 (선택)"
            }
          },
          required: []
        }
      },
      {
        name: "submit_feedback",
        description: "운동 완료 후 피드백을 제출합니다. '적당했어', '좀 쉬웠어', '힘들었어', '강도 올려줘', '강도 낮춰줘', '좋았어', '스쿼트가 어려웠어' 등의 피드백에 사용합니다.",
        input_schema: {
          type: "object",
          properties: {
            feedback_text: {
              type: "string",
              description: "사용자가 말한 피드백 원문 (예: '적당했어', '힘들었어', '스쿼트가 어려웠어')"
            },
            feedback_type: {
              type: "string",
              enum: %w[just_right too_easy too_hard specific],
              description: "피드백 유형: just_right(적당), too_easy(쉬움), too_hard(힘듦), specific(특정 운동 언급)"
            }
          },
          required: %w[feedback_text feedback_type]
        }
      }
    ]

    # Add routine modification tools only if routine_id is present
    if routine_id.present?
      tools += [
        {
          name: "replace_exercise",
          description: "루틴에서 특정 운동을 다른 운동으로 교체합니다. '벤치 말고 다른 거', '이거 힘들어', '어깨 아파서 못해' 등의 요청에 사용합니다.",
          input_schema: {
            type: "object",
            properties: {
              exercise_name: {
                type: "string",
                description: "교체할 운동 이름"
              },
              reason: {
                type: "string",
                description: "교체 이유 (부상, 장비 없음 등)"
              }
            },
            required: %w[exercise_name]
          }
        },
        {
          name: "add_exercise",
          description: "루틴에 새 운동을 추가합니다. '팔운동 더 하고 싶어', '플랭크도 넣어줘' 등의 요청에 사용합니다.",
          input_schema: {
            type: "object",
            properties: {
              exercise_name: {
                type: "string",
                description: "추가할 운동 이름"
              },
              sets: {
                type: "integer",
                description: "세트 수 (기본값: 3)"
              },
              reps: {
                type: "integer",
                description: "반복 횟수 (기본값: 10)"
              }
            },
            required: %w[exercise_name]
          }
        },
        {
          name: "regenerate_routine",
          description: "루틴 전체를 새로 만듭니다. '마음에 안 들어', '다른 루틴으로', '전부 바꿔줘' 등의 요청에 사용합니다.",
          input_schema: {
            type: "object",
            properties: {
              goal: {
                type: "string",
                description: "새 루틴의 목표"
              }
            },
            required: []
          }
        },
        {
          name: "delete_routine",
          description: "현재 루틴을 삭제합니다. 완료된 루틴은 삭제할 수 없습니다. '루틴 삭제해줘', '이 루틴 지워줘' 등의 요청에 사용합니다.",
          input_schema: {
            type: "object",
            properties: {
              confirm: {
                type: "boolean",
                description: "삭제 확인 (true일 때만 삭제)"
              }
            },
            required: %w[confirm]
          }
        }
      ]
    end

    tools
  end

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
    when "regenerate_routine"
      handle_regenerate_routine(input)
    when "delete_routine"
      handle_delete_routine(input)
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
      data: { routine: routine, program: program_info }
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
          existing_routine_id: today_routine.id
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
        data: { condition: condition }
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
        routine: routine_result
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
        data: { records: [ record_item ] }
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
        remaining_replacements: rate_check[:remaining]
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
        added_exercise: exercise
      }
    )
  end

  def handle_regenerate_routine(input)
    routine = current_routine
    return error_response("수정할 루틴을 찾을 수 없어요.") unless routine
    return error_response("이미 지난 루틴은 수정할 수 없어요.") unless routine_editable?(routine)

    rate_check = RoutineRateLimiter.check_and_increment!(user: user, action: :routine_regeneration)
    return error_response(rate_check[:error]) unless rate_check[:allowed]

    result = AiTrainer::RoutineService.generate(
      user: user,
      day_of_week: routine.day_number,
      goal: input["goal"]
    )

    return error_response("루틴 재생성에 실패했어요.") unless result&.dig(:routine_id)

    routine.routine_exercises.destroy_all

    result[:exercises]&.each_with_index do |ex, idx|
      routine.routine_exercises.create!(
        exercise_name: ex[:exercise_name],
        order_index: idx,
        sets: ex[:sets],
        reps: ex[:reps],
        target_muscle: ex[:target_muscle],
        rest_duration_seconds: ex[:rest_seconds] || 60,
        how_to: ex[:instructions],
        weight_description: ex[:weight_description] || ex[:weight_guide]
      )
    end

    routine.update!(
      workout_type: result[:training_type],
      estimated_duration: result[:estimated_duration_minutes]
    )

    success_response(
      message: "새로운 루틴으로 다시 만들었어요! 💪\n\n#{format_regenerated_routine_message(routine.reload)}",
      intent: "REGENERATE_ROUTINE",
      data: {
        routine: routine.reload,
        remaining_regenerations: rate_check[:remaining]
      }
    )
  end

  def handle_delete_routine(input)
    routine = current_routine
    return error_response("삭제할 루틴을 찾을 수 없어요.") unless routine
    return error_response("이미 지난 루틴은 삭제할 수 없어요.") unless routine_editable?(routine)

    unless input["confirm"] == true
      return error_response("삭제를 확인해주세요.")
    end

    routine_id = routine.id
    routine.destroy!

    success_response(
      message: "루틴을 삭제했어요. 새로운 루틴이 필요하면 말씀해주세요!",
      intent: "DELETE_ROUTINE",
      data: { deleted_routine_id: routine_id }
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

  def format_long_term_plan_message(long_term_plan, profile)
    name = user.name || "회원"
    goal = profile.fitness_goal || "건강"
    tier = tier_korean(profile.tier || "beginner")

    msg = "## 📋 #{name}님의 맞춤 운동 계획\n\n"
    msg += "**🎯 목표:** #{goal}\n"
    msg += "**💪 레벨:** #{tier}\n"
    msg += "**📅 주간 스케줄:** #{long_term_plan[:weekly_split]}\n\n"

    msg += "### 🗓️ 주간 운동 스케줄\n"
    long_term_plan[:weekly_schedule]&.each do |day|
      day_names = %w[일 월 화 수 목 금 토]
      day_name = day_names[day[:day]] || "#{day[:day]}일"
      msg += "- **#{day_name}요일:** #{day[:focus]}\n"
    end

    msg += "\n### 📈 훈련 전략\n"
    msg += "#{long_term_plan[:description]}\n\n"

    msg += "### 🔥 점진적 과부하\n"
    msg += "#{long_term_plan[:progression_strategy]}\n\n"

    msg += "### ⏰ 예상 결과\n"
    msg += "#{long_term_plan[:estimated_timeline]}\n\n"

    msg += "오늘 운동을 시작해볼까요? \"오늘 루틴 만들어줘\"라고 말씀해주세요! 💪"
    msg
  end

  # ============================================
  # General Chat with RAG
  # ============================================

  def handle_general_chat_with_rag
    result = AiTrainer::ChatService.general_chat(
      user: user,
      message: message,
      session_id: session_id
    )

    # Cache the response for future identical questions
    answer = result[:message] || "무엇을 도와드릴까요?"
    cache_response(answer)

    success_response(
      message: result[:message] || "무엇을 도와드릴까요?",
      intent: "GENERAL_CHAT",
      data: {
        knowledge_used: result[:knowledge_used],
        session_id: result[:session_id]
      }
    )
  end

  # ============================================
  # Daily Greeting (AI First - All Users)
  # ============================================

  def needs_daily_greeting?
    # Only trigger on empty message or "start"/"시작"
    return false unless message.blank? || message == "시작" || message == "start"

    # Must have completed onboarding
    profile = user.user_profile
    return false unless profile&.onboarding_completed_at

    true
  end

  def handle_daily_greeting
    profile = user.user_profile
    today = Time.current.in_time_zone("Asia/Seoul").to_date

    # Get recent workout history
    yesterday_session = get_workout_session(today - 1.day)
    last_week_same_day = get_workout_session(today - 7.days)

    # Summarize sessions for display
    yesterday_summary = yesterday_session ? summarize_session(yesterday_session) : nil
    last_week_summary = last_week_same_day ? summarize_session(last_week_same_day) : nil

    # Build greeting message
    greeting = build_daily_greeting(
      profile: profile,
      yesterday: yesterday_summary,
      last_week: last_week_summary,
      today: today
    )

    success_response(
      message: greeting,
      intent: "DAILY_GREETING",
      data: {
        yesterday_workout: yesterday_summary,
        last_week_workout: last_week_summary,
        suggestions: [
          "좋아! 오늘 운동 시작하자",
          "오늘은 좀 피곤해",
          "컨디션 좋아! 강도 올려줘"
        ]
      }
    )
  end

  def get_workout_session(date)
    user.workout_sessions
        .includes(:workout_sets)
        .where(start_time: date.beginning_of_day..date.end_of_day)
        .order(start_time: :desc)
        .first
  end

  def summarize_session(session)
    return nil unless session

    # Get workout sets for this session
    sets = session.workout_sets.order(:created_at)
    exercises_by_name = sets.group_by(&:exercise_name)

    {
      date: session.start_time.to_date.to_s,
      day_korean: session.name || "운동",
      duration_minutes: session.total_duration ? (session.total_duration / 60) : nil,
      exercises: exercises_by_name.map do |name, exercise_sets|
        best = exercise_sets.max_by { |s| (s.weight || 0).to_f }
        {
          name: name,
          sets: exercise_sets.size,
          best_set: best ? { "weight" => best.weight, "reps" => best.reps } : nil
        }
      end,
      total_volume: sets.sum { |s| (s.weight || 0).to_f * (s.reps || 0).to_i }.round(1),
      completed: session.status == "completed"
    }.with_indifferent_access
  end

  def build_daily_greeting(profile:, yesterday:, last_week:, today:)
    name = user.name || "회원"
    day_names = %w[일 월 화 수 목 금 토]
    today_name = day_names[today.wday]

    lines = []
    lines << "#{name}님, 안녕하세요! 💪"
    lines << ""

    # Yesterday's workout summary
    if yesterday
      Rails.logger.info("[DailyGreeting] Yesterday data: #{yesterday.inspect}")
      day_name = yesterday[:day_korean] || yesterday["day_korean"] || "운동"
      duration = yesterday[:duration_minutes] || yesterday["duration_minutes"]
      lines << "📊 **어제 운동 기록**"
      lines << "- #{day_name} (#{duration || '?'}분)"
      exercises = yesterday[:exercises] || []
      exercises.first(3).each do |ex|
        if ex[:best_set]
          lines << "  • #{ex[:name]}: #{ex[:best_set]['weight']}kg x #{ex[:best_set]['reps']}회"
        else
          lines << "  • #{ex[:name]}: #{ex[:sets]}세트"
        end
      end
      if exercises.size > 3
        lines << "  • ... 외 #{exercises.size - 3}개"
      end
      lines << ""
    end

    # Last week same day comparison
    if last_week
      lines << "📅 **지난주 #{today_name}요일**"
      lines << "- #{last_week[:day_korean]} 수행"
      volume = last_week[:total_volume] || 0
      if volume > 0
        lines << "- 총 볼륨: #{volume.to_i}kg"
      end
      lines << ""
    end

    # No recent workout
    if !yesterday && !last_week
      lines << "최근 운동 기록이 없네요. 오늘부터 다시 시작해볼까요? 🔥"
      lines << ""
    end

    # Ask about today's condition
    lines << "---"
    lines << ""
    lines << "오늘 **컨디션**은 어떠세요?"
    lines << ""
    lines << "1️⃣ 컨디션 좋아! → 강도 높여서"
    lines << "2️⃣ 보통이야 → 평소처럼"
    lines << "3️⃣ 좀 피곤해 → 가볍게"

    lines.join("\n")
  end

  # Check if user just completed onboarding and has no routines yet
  # No regex parsing - just check state, Claude will decide based on context
  def wants_today_routine?
    return false if message.blank?

    # Skip if user still needs level assessment (AI consultation)
    return false if needs_level_assessment?

    # Reload profile to get fresh data (fix stale association)
    profile = UserProfile.find_by(user_id: user.id)
    Rails.logger.info("[wants_today_routine?] user_id=#{user.id}, onboarding_completed_at=#{profile&.onboarding_completed_at}")
    return false unless profile&.onboarding_completed_at.present?

    # Check if no routines exist yet (just finished program creation)
    # If true, any positive response should trigger routine generation
    routine_count = WorkoutRoutine.where(user_id: user.id).count
    Rails.logger.info("[wants_today_routine?] routine_count=#{routine_count}, message=#{message}")

    # If onboarding complete + no routines yet, assume user wants first routine
    # (they just saw "오늘 운동 시작할까요?" prompt)
    routine_count == 0
  end

  def handle_show_today_routine
    # Get user's training program (should exist after onboarding)
    program = user.active_training_program

    # Generate today's routine using the same method as handle_generate_routine
    day_of_week = Time.current.wday
    day_of_week = day_of_week == 0 ? 7 : day_of_week

    result = AiTrainer.generate_routine(
      user: user,
      day_of_week: day_of_week,
      condition_inputs: nil,
      recent_feedbacks: user.workout_feedbacks.order(created_at: :desc).limit(5)
    )

    if result.is_a?(Hash) && result[:success] == false
      return error_response(result[:error] || "루틴 생성에 실패했어요.")
    end

    # Build program info for display
    program_info = if program
      {
        name: program.name,
        current_week: program.current_week,
        total_weeks: program.total_weeks,
        phase: program.current_phase,
        volume_modifier: program.current_volume_modifier
      }
    end

    # Format response with program context
    lines = []
    lines << "오늘의 운동 루틴이에요! 💪"
    lines << ""

    if program_info
      lines << "🗓️ **#{program_info[:name]}** - #{program_info[:current_week]}/#{program_info[:total_weeks]}주차 (#{program_info[:phase]})"
    end

    lines << "📋 **#{result[:day_korean] || '오늘의 운동'}**"
    lines << "⏱️ 예상 시간: #{result[:estimated_duration_minutes] || 45}분"
    lines << ""
    lines << "**운동 목록:**"

    exercises = result[:exercises] || []
    exercises.each_with_index do |ex, idx|
      name = ex[:exercise_name] || ex["exercise_name"] || ex[:name] || ex["name"]
      sets = ex[:sets] || ex["sets"] || 3
      reps = ex[:reps] || ex["reps"] || 10
      lines << "#{idx + 1}. **#{name}** - #{sets}세트 x #{reps}회"
    end

    lines << ""
    lines << "운동을 마치면 **\"운동 끝났어\"** 라고 말씀해주세요!"
    lines << "피드백을 받아 다음 루틴을 최적화해드릴게요 📈"

    success_response(
      message: lines.join("\n"),
      intent: "GENERATE_ROUTINE",
      data: {
        routine: result,
        program: program_info,
        suggestions: ["운동 시작!", "운동 하나 교체해줘", "나중에 할게"]
      }
    )
  end
  
  def save_routine_to_db(result)
    today = Date.current
    program = user.active_training_program

    routine = WorkoutRoutine.create!(
      user_id: user.id,
      level: user.user_profile&.tier || "beginner",
      week_number: program&.current_week || 1,
      day_number: today.cwday,  # Day of week (1=Mon, 7=Sun)
      workout_type: result[:workout_type] || "full_body",
      day_of_week: result[:day_korean] || today.strftime("%A"),
      estimated_duration: result[:estimated_duration_minutes] || 45,
      generated_at: Time.current
    )
    
    result[:exercises].each_with_index do |ex, idx|
      RoutineExercise.create!(
        workout_routine_id: routine.id,
        exercise_id: ex[:exercise_id] || ex["exercise_id"],
        exercise_name: ex[:exercise_name] || ex["exercise_name"] || ex[:name] || ex["name"],
        sets: ex[:sets] || ex["sets"] || 3,
        reps: ex[:reps] || ex["reps"] || 10,
        order_index: idx + 1
      )
    end
    
    routine
  rescue => e
    Rails.logger.error("Failed to save routine: #{e.message}")
    nil
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
        suggestions: ["내일 운동 미리보기", "이번 주 기록 보기", "프로그램 진행 상황"]
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

    if today_routine
      lines << "📊 **오늘의 운동 기록**"
      lines << "• #{today_routine.day_of_week}"
      lines << "• 예상 시간: #{today_routine.estimated_duration}분"
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

    today = Time.current.in_time_zone("Asia/Seoul").to_date.to_s

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

    # Build routine generation request
    routine_request = {
      focus: suggested_focus[:focus],
      intensity: intensity,
      condition: condition,
      duration_minutes: suggested_focus[:duration]
    }

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
    today = Time.current.in_time_zone("Asia/Seoul")
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

  def format_routine_for_display(routine)
    return "루틴을 준비하지 못했어요." unless routine

    lines = []
    lines << "📋 **#{routine[:day_korean] || '오늘의 루틴'}**"
    lines << "⏱️ 예상 시간: #{routine[:estimated_duration_minutes] || 60}분"
    lines << ""

    exercises = routine[:exercises] || []
    exercises.each_with_index do |ex, i|
      name = ex[:exercise_name] || ex["exercise_name"]
      sets = ex[:sets] || ex["sets"]
      reps = ex[:reps] || ex["reps"]
      lines << "#{i + 1}. **#{name}** - #{sets}세트 x #{reps}회"
    end

    lines << ""
    lines << "준비되면 '운동 시작'이라고 말씀해주세요! 🔥"

    lines.join("\n")
  end

  # ============================================
  # Welcome Message (First Chat After Onboarding)
  # ============================================

  def needs_welcome_message?
    return false if message.present? && message != "시작" && message != "start"

    profile = user.user_profile
    return false unless profile&.onboarding_completed_at

    # Welcome if onboarding completed recently AND no workout routines yet
    recently_onboarded = profile.onboarding_completed_at > 5.minutes.ago
    no_routines_yet = !user.workout_routines.exists?

    recently_onboarded && no_routines_yet
  end

  def handle_welcome_message
    profile = user.user_profile
    tier = profile&.tier || "beginner"
    level = profile&.numeric_level || 1
    goal = profile&.fitness_goal || "건강"

    # Get consultation data for personalized plan
    consultation_data = profile&.fitness_factors&.dig("collected_data") || {}

    # Build long-term plan explanation
    long_term_plan = build_long_term_plan(profile, consultation_data)

    prompt = <<~PROMPT
      새로 온보딩을 완료한 사용자에게 장기 운동 계획을 설명하고 첫 루틴을 제안해주세요.

      ## 사용자 정보
      - 이름: #{user.name || '회원'}
      - 레벨: #{level} (#{tier_korean(tier)})
      - 목표: #{goal}
      - 키: #{profile&.height}cm
      - 체중: #{profile&.weight}kg
      - 운동 빈도: #{consultation_data['frequency'] || '주 3회'}
      - 운동 환경: #{consultation_data['environment'] || '헬스장'}
      - 부상/주의사항: #{consultation_data['injuries'] || '없음'}
      - 집중 부위: #{consultation_data['focus_areas'] || '전체'}

      ## 장기 운동 계획
      #{long_term_plan[:description]}

      ## 주간 스플릿
      #{long_term_plan[:weekly_split]}

      ## 응답 규칙
      1. 환영 인사 (이름 포함)
      2. 상담 내용 바탕으로 맞춤 장기 계획 설명 (주간 스플릿, 목표 달성 전략)
      3. "지금 바로 오늘의 루틴을 만들어드릴게요!" 라고 말하며 루틴 생성 예고
      4. 친근하고 격려하는 톤
      5. 4-6문장 정도로 충분히 설명
      6. 이모지 적절히 사용
      7. **마지막에 반드시** "잠시만요, 오늘의 맞춤 루틴을 준비할게요... 💪" 라고 끝내기
    PROMPT

    response = AiTrainer::LlmGateway.chat(
      prompt: prompt,
      task: :welcome_with_plan,
      system: "당신은 친근하면서도 전문적인 피트니스 AI 트레이너입니다. 한국어로 응답하세요."
    )

    welcome_text = if response[:success]
      response[:content]
    else
      default_welcome_with_plan(profile, long_term_plan)
    end

    # Auto-generate first routine
    first_routine = generate_first_routine

    if first_routine && first_routine[:exercises].present?
      # Combine welcome message with routine
      routine_message = format_first_routine_message(first_routine)
      full_message = "#{welcome_text}\n\n---\n\n#{routine_message}"

      success_response(
        message: full_message,
        intent: "WELCOME_WITH_ROUTINE",
        data: {
          is_first_chat: true,
          user_profile: {
            level: level,
            tier: tier,
            goal: goal
          },
          long_term_plan: long_term_plan,
          routine: first_routine,
          suggestions: [
            "운동 시작할게!",
            "이 운동 대신 다른 거 추천해줘",
            "운동 순서 바꿔도 될까?"
          ]
        }
      )
    else
      # Fallback: just welcome message with suggestion
      success_response(
        message: welcome_text,
        intent: "WELCOME",
        data: {
          is_first_chat: true,
          user_profile: {
            level: level,
            tier: tier,
            goal: goal
          },
          long_term_plan: long_term_plan,
          suggestions: [
            "오늘 루틴 만들어줘",
            "내 레벨에 맞는 운동 추천해줘",
            "운동 어떻게 시작하면 좋을까?"
          ]
        }
      )
    end
  end

  def build_long_term_plan(profile, consultation_data)
    tier = profile&.tier || "beginner"
    goal = profile&.fitness_goal || "건강"
    frequency = consultation_data["frequency"] || "주 3회"
    focus_areas = consultation_data["focus_areas"]

    # Parse frequency
    freq_match = frequency.match(/(\d+)/)
    days_per_week = freq_match ? freq_match[1].to_i : 3
    days_per_week = [[days_per_week, 2].max, 6].min  # Clamp between 2-6

    # Build weekly split based on frequency and level
    weekly_split = build_weekly_split(tier, days_per_week, focus_areas)

    # Build plan description
    description = build_plan_description(tier, goal, days_per_week)

    {
      tier: tier,
      goal: goal,
      days_per_week: days_per_week,
      weekly_split: weekly_split[:description],
      weekly_schedule: weekly_split[:schedule],
      description: description,
      progression_strategy: build_progression_strategy(tier),
      estimated_timeline: estimate_goal_timeline(tier, goal)
    }
  end

  def build_weekly_split(tier, days_per_week, focus_areas)
    case tier
    when "beginner"
      # 초급: 전신 운동
      if days_per_week <= 3
        {
          description: "전신 운동 (주 #{days_per_week}회)",
          schedule: (1..days_per_week).map { |d| { day: d, focus: "전신", muscles: %w[legs chest back shoulders core] } }
        }
      else
        {
          description: "상하체 분할 (주 #{days_per_week}회)",
          schedule: (1..days_per_week).map { |d| d.odd? ? { day: d, focus: "상체", muscles: %w[chest back shoulders arms] } : { day: d, focus: "하체", muscles: %w[legs core] } }
        }
      end
    when "intermediate"
      # 중급: 상하체 분할 또는 PPL
      if days_per_week <= 4
        {
          description: "상하체 분할 (주 #{days_per_week}회)",
          schedule: [
            { day: 1, focus: "상체", muscles: %w[chest back shoulders arms] },
            { day: 2, focus: "하체", muscles: %w[legs core] },
            { day: 3, focus: "상체", muscles: %w[chest back shoulders arms] },
            { day: 4, focus: "하체", muscles: %w[legs core] }
          ].first(days_per_week)
        }
      else
        {
          description: "PPL 분할 (주 #{days_per_week}회)",
          schedule: [
            { day: 1, focus: "밀기 (Push)", muscles: %w[chest shoulders triceps] },
            { day: 2, focus: "당기기 (Pull)", muscles: %w[back biceps] },
            { day: 3, focus: "하체 (Legs)", muscles: %w[legs core] },
            { day: 4, focus: "밀기 (Push)", muscles: %w[chest shoulders triceps] },
            { day: 5, focus: "당기기 (Pull)", muscles: %w[back biceps] },
            { day: 6, focus: "하체 (Legs)", muscles: %w[legs core] }
          ].first(days_per_week)
        }
      end
    when "advanced"
      # 고급: PPL 또는 4-5분할
      if days_per_week >= 5
        {
          description: "5분할 (주 #{days_per_week}회)",
          schedule: [
            { day: 1, focus: "가슴", muscles: %w[chest] },
            { day: 2, focus: "등", muscles: %w[back] },
            { day: 3, focus: "어깨", muscles: %w[shoulders] },
            { day: 4, focus: "하체", muscles: %w[legs] },
            { day: 5, focus: "팔", muscles: %w[biceps triceps] },
            { day: 6, focus: "약점 보완", muscles: focus_areas&.split(",")&.map(&:strip) || %w[core] }
          ].first(days_per_week)
        }
      else
        {
          description: "PPL 분할 (주 #{days_per_week}회)",
          schedule: [
            { day: 1, focus: "밀기 (Push)", muscles: %w[chest shoulders triceps] },
            { day: 2, focus: "당기기 (Pull)", muscles: %w[back biceps] },
            { day: 3, focus: "하체 (Legs)", muscles: %w[legs core] },
            { day: 4, focus: "밀기 (Push)", muscles: %w[chest shoulders triceps] }
          ].first(days_per_week)
        }
      end
    else
      {
        description: "전신 운동 (주 3회)",
        schedule: [
          { day: 1, focus: "전신", muscles: %w[legs chest back shoulders core] },
          { day: 2, focus: "전신", muscles: %w[legs chest back shoulders core] },
          { day: 3, focus: "전신", muscles: %w[legs chest back shoulders core] }
        ]
      }
    end
  end

  def build_plan_description(tier, goal, days_per_week)
    goal_strategies = {
      "근비대" => "근육량 증가를 위해 중량을 점진적으로 늘리고, 8-12회 반복에 집중합니다.",
      "다이어트" => "체지방 감소를 위해 서킷 트레이닝과 고반복 운동을 병행합니다.",
      "체력 향상" => "전반적인 체력 증진을 위해 복합 운동과 유산소를 균형있게 배치합니다.",
      "건강" => "건강 유지를 위해 모든 근육군을 균형있게 훈련합니다.",
      "strength" => "근력 향상을 위해 무거운 무게로 낮은 반복수(3-6회)에 집중합니다."
    }

    tier_approaches = {
      "beginner" => "기본 동작을 완벽히 익히는 것이 우선입니다. 가벼운 무게로 자세를 잡고, 2-3개월 후 무게를 늘려갑니다.",
      "intermediate" => "이제 점진적 과부하가 핵심입니다. 매주 조금씩 무게나 반복 수를 늘려가세요.",
      "advanced" => "주기화 훈련으로 근력과 근비대를 번갈아 집중합니다. 디로드 주간도 중요합니다."
    }

    strategy = goal_strategies[goal] || goal_strategies["건강"]
    approach = tier_approaches[tier] || tier_approaches["beginner"]

    "#{strategy} #{approach}"
  end

  def build_progression_strategy(tier)
    case tier
    when "beginner"
      "처음 4-6주: 동작 학습 기간 → 이후 매주 2.5% 또는 1-2회 증가"
    when "intermediate"
      "주당 2.5-5% 무게 증가, 4주마다 디로드 주간 포함"
    when "advanced"
      "3주 증가 + 1주 디로드 사이클, 비선형 주기화 적용"
    else
      "매주 조금씩 무게 또는 반복 수를 늘려가세요"
    end
  end

  def estimate_goal_timeline(tier, goal)
    base_weeks = case goal
    when "근비대" then 12
    when "다이어트" then 8
    when "체력 향상" then 6
    when "건강" then "지속적"
    else 8
    end

    tier_modifier = case tier
    when "beginner" then 1.5
    when "intermediate" then 1.0
    when "advanced" then 0.8
    else 1.0
    end

    if base_weeks.is_a?(Integer)
      adjusted = (base_weeks * tier_modifier).round
      "약 #{adjusted}주 후 눈에 띄는 변화 기대"
    else
      "꾸준히 운동하면 건강 유지 가능"
    end
  end

  def generate_first_routine
    day_of_week = Time.current.wday
    day_of_week = day_of_week == 0 ? 7 : day_of_week
    day_of_week = [day_of_week, 5].min  # Cap at Friday for first routine

    AiTrainer.generate_routine(
      user: user,
      day_of_week: day_of_week,
      condition_inputs: { energy_level: 4, notes: "첫 운동 - 적응 기간" },  # Slightly easier for first workout
      goal: user.user_profile&.fitness_goal
    )
  rescue StandardError => e
    Rails.logger.error("[ChatService] Failed to generate first routine: #{e.message}")
    nil
  end

  def format_first_routine_message(routine)
    msg = "## 🎯 오늘의 첫 루틴이 준비됐어요!\n\n"
    msg += "📋 **#{routine[:day_korean] || routine['day_korean']}** - #{routine[:fitness_factor_korean] || routine['fitness_factor_korean'] || '맞춤 훈련'}\n"
    msg += "⏱️ 예상 시간: #{routine[:estimated_duration_minutes] || routine['estimated_duration_minutes'] || 45}분\n\n"

    exercises = routine[:exercises] || routine["exercises"] || []
    msg += "**운동 목록:**\n"
    exercises.each_with_index do |ex, idx|
      name = ex[:exercise_name] || ex["exercise_name"]
      sets = ex[:sets] || ex["sets"]
      reps = ex[:reps] || ex["reps"]
      work_seconds = ex[:work_seconds] || ex["work_seconds"]

      if work_seconds.present?
        msg += "#{idx + 1}. #{name} - #{sets}세트 x #{work_seconds}초\n"
      else
        msg += "#{idx + 1}. #{name} - #{sets}세트 x #{reps}회\n"
      end
    end

    # Add coach message if available
    if routine[:notes].present? && routine[:notes].any?
      msg += "\n💡 **코치 팁:** #{routine[:notes].first}"
    end

    msg += "\n\n준비되면 \"운동 시작\"이라고 말씀해주세요! 함께 해볼까요? 💪"
    msg
  end

  def default_welcome_with_plan(profile, long_term_plan)
    name = user.name || "회원"
    goal = profile&.fitness_goal || "건강"
    tier = profile&.tier || "beginner"

    tier_name = tier_korean(tier)
    weekly_split = long_term_plan[:weekly_split]

    "#{name}님, 환영합니다! 🎉\n\n" \
    "상담 내용을 바탕으로 #{name}님만의 운동 계획을 세웠어요.\n\n" \
    "📌 **목표:** #{goal}\n" \
    "📌 **레벨:** #{tier_name}\n" \
    "📌 **주간 스케줄:** #{weekly_split}\n\n" \
    "#{long_term_plan[:description]}\n\n" \
    "잠시만요, 오늘의 맞춤 루틴을 준비할게요... 💪"
  end

  def default_welcome_message(profile)
    name = user.name || "회원"
    goal = profile&.fitness_goal || "건강"

    "#{name}님, 환영합니다! 🎉\n\n" \
    "#{goal} 목표로 함께 운동해봐요. " \
    "\"오늘 루틴 만들어줘\"라고 말씀해주시면 맞춤 운동을 준비해드릴게요! 💪"
  end

  def tier_korean(tier)
    { "none" => "입문", "beginner" => "초급", "intermediate" => "중급", "advanced" => "고급" }[tier] || "입문"
  end

  # Build conversation context summary for system prompt (brief)
  def conversation_context_summary
    recent = ChatMessage.where(user_id: user.id)
                        .order(created_at: :desc)
                        .limit(5)

    return "새 대화입니다." if recent.empty?

    summary = recent.reverse.map do |msg|
      role = msg.role == "user" ? "사용자" : "트레이너"
      "#{role}: #{msg.content.to_s.truncate(50)}"
    end.join("\n")

    summary
  rescue StandardError => e
    Rails.logger.warn("[ChatService] Failed to build conversation context: #{e.message}")
    "대화 컨텍스트를 불러오지 못했습니다."
  end

  # Build full conversation history for messages array (better context)
  # This allows Claude to understand the full conversation flow
  def build_conversation_history
    recent = ChatMessage.where(user_id: user.id)
                        .order(created_at: :desc)
                        .limit(15)  # Last 15 messages for good context balance

    return [] if recent.empty?

    recent.reverse.map do |msg|
      {
        role: msg.role == "user" ? "user" : "assistant",
        content: msg.content.to_s
      }
    end
  rescue StandardError => e
    Rails.logger.warn("[ChatService] Failed to build conversation history: #{e.message}")
    []
  end

  # ============================================
  # Level Assessment (Special Flow)
  # ============================================

  def needs_level_assessment?
    AiTrainer::LevelAssessmentService.needs_assessment?(user)
  end

  def handle_level_assessment
    result = AiTrainer::LevelAssessmentService.assess(user: user, message: message)

    if result[:success]
      # Use TRAINING_PROGRAM intent when program is created (is_complete)
      intent = result[:is_complete] ? "TRAINING_PROGRAM" : "CONSULTATION"

      # Extract suggestions from AI message for button display
      suggestions = extract_suggestions_from_message(result[:message])

      success_response(
        message: result[:message],
        intent: intent,
        data: {
          is_complete: result[:is_complete],
          assessment: result[:assessment],
          suggestions: suggestions.presence
        }
      )
    else
      error_response(result[:error] || "수준 파악에 실패했어요.")
    end
  end

  # Extract choice options from AI message for button display
  # Patterns: "A? B?", "(A/B/C)", "1. A 2. B", numbered emoji options
  def extract_suggestions_from_message(message)
    return [] if message.blank?

    suggestions = []

    # Pattern 1: Numbered emoji options (1️⃣, 2️⃣, 3️⃣)
    # Example: "1️⃣ 네, 오늘 운동 루틴 보여줘"
    emoji_pattern = /([1-9]️⃣[^\n]+)/
    emoji_matches = message.scan(emoji_pattern).flatten
    if emoji_matches.length >= 2
      suggestions = emoji_matches.map do |match|
        # Remove emoji prefix and clean up
        match.gsub(/^[1-9]️⃣\s*/, "").strip
      end
      return suggestions.first(4) if suggestions.any?
    end

    # Pattern 2: "A? B?" format (Korean question options)
    # Example: "아침형? 저녁형?"
    question_pattern = /([가-힣a-zA-Z0-9]+)\?\s*([가-힣a-zA-Z0-9]+)\?/
    if message =~ question_pattern
      suggestions = [$1, $2]
      return suggestions if suggestions.length >= 2
    end

    # Pattern 3: "(A/B/C)" format
    # Example: "(헬스장/홈트/기구 유무)"
    paren_pattern = /\(([^)]+[\/,][^)]+)\)/
    paren_matches = message.scan(paren_pattern).flatten
    paren_matches.each do |match|
      options = match.split(%r{[/,]}).map(&:strip).reject(&:blank?)
      if options.length >= 2
        suggestions = options
        return suggestions.first(4)
      end
    end

    # Pattern 4: Numbered list "1. A 2. B" format
    # Example: "1. 근비대 2. 다이어트 3. 체력 향상"
    numbered_pattern = /\d+\.\s*([^\d\n]+?)(?=\s*\d+\.|$)/
    numbered_matches = message.scan(numbered_pattern).flatten.map(&:strip).reject(&:blank?)
    if numbered_matches.length >= 2
      suggestions = numbered_matches.first(4)
      return suggestions
    end

    suggestions
  end

  # ============================================
  # Helpers
  # ============================================

  # Check if routine can be edited (only today's routine is editable)
  def routine_editable?(routine)
    return false unless routine
    routine.created_at >= Time.current.beginning_of_day
  end

  def current_routine
    return @current_routine if defined?(@current_routine)

    @current_routine = if routine_id.present?
      # Try direct ID lookup first (normal case: DB ID)
      found = user.workout_routines.find_by(id: routine_id)

      # Fallback: If ID looks like "RT-{level}-{timestamp}-{hex}" format
      # This handles edge cases where DB save succeeded but ID wasn't updated in response
      if found.nil? && routine_id.to_s.start_with?("RT-")
        Rails.logger.warn("[ChatService] Routine ID '#{routine_id}' is AI-generated format, attempting fallback lookup")

        # Try to extract timestamp from RT-5-1769931298-21ed8d66 format
        if routine_id =~ /RT-\d+-(\d+)-/
          timestamp = Regexp.last_match(1).to_i
          # Find routine created within 5 minutes of that timestamp
          time_range = Time.at(timestamp - 300)..Time.at(timestamp + 300)
          found = user.workout_routines.where(created_at: time_range).order(created_at: :desc).first
          Rails.logger.info("[ChatService] Found routine by timestamp range: #{found&.id}")
        end

        # Last resort: use most recent incomplete routine
        found ||= user.workout_routines.where(is_completed: false).order(created_at: :desc).first
      end

      found
    end
  end

  def find_exercise_in_routine(routine, exercise_name)
    return nil unless exercise_name.present?

    name_lower = exercise_name.downcase.gsub(/\s+/, "")

    # Load exercises from DB
    exercises = routine.routine_exercises.reload

    Rails.logger.info("[ChatService] Looking for '#{exercise_name}' in routine #{routine.id}")
    Rails.logger.info("[ChatService] Routine has #{exercises.count} exercises: #{exercises.map(&:exercise_name).join(', ')}")

    found = exercises.find do |ex|
      ex_name = ex.exercise_name.to_s.downcase.gsub(/\s+/, "")
      ex_name.include?(name_lower) || name_lower.include?(ex_name)
    end

    Rails.logger.info("[ChatService] Found exercise: #{found&.exercise_name || 'nil'}")
    found
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

  def format_routine_message(routine, program_info = nil)
    msg = "오늘의 루틴을 준비했어요! 💪\n\n"

    # Show program context if available
    if program_info
      phase = program_info[:phase] || program_info["phase"]
      week = program_info[:current_week] || program_info["current_week"]
      total = program_info[:total_weeks] || program_info["total_weeks"]
      if phase && week && total
        msg += "🗓️ **#{program_info[:name] || '프로그램'}** - #{week}/#{total}주차 (#{phase})\n"
      end
    end

    msg += "📋 **#{routine[:day_korean] || routine['day_korean']}** - #{routine[:fitness_factor_korean] || routine['fitness_factor_korean']}\n"
    msg += "⏱️ 예상 시간: #{routine[:estimated_duration_minutes] || routine['estimated_duration_minutes']}분\n\n"

    exercises = routine[:exercises] || routine["exercises"] || []
    msg += "**운동 목록:**\n"
    exercises.first(5).each do |ex|
      name = ex[:exercise_name] || ex["exercise_name"]
      sets = ex[:sets] || ex["sets"]
      reps = ex[:reps] || ex["reps"]
      msg += "• #{name} #{sets}세트 x #{reps}회\n"
    end

    msg += "• ... 외 #{exercises.length - 5}개\n" if exercises.length > 5
    msg += "\n운동 시작할 준비가 되면 알려주세요!"
    msg
  end

  def format_regenerated_routine_message(routine)
    exercises = routine.routine_exercises.order(:order_index)

    msg = "**운동 목록:**\n"
    exercises.first(5).each do |ex|
      msg += "• #{ex.exercise_name} #{ex.sets}세트 x #{ex.reps}회\n"
    end

    msg += "• ... 외 #{exercises.length - 5}개\n" if exercises.length > 5
    msg += "\n운동 시작할 준비가 되면 알려주세요!"
    msg
  end

  # LLM이 전달한 컨디션 문자열을 해시로 변환
  # 복잡한 파싱 없이 문자열 그대로 전달 - ToolBasedRoutineGenerator가 LLM으로 해석
  def parse_condition_string(condition_str)
    return nil if condition_str.blank?

    # 문자열 그대로 notes에 담아서 전달
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

  def success_response(message:, intent:, data:)
    { success: true, message: message, intent: intent, data: data, error: nil }
  end

  def error_response(error_message)
    { success: false, message: nil, intent: nil, data: nil, error: error_message }
  end
end
