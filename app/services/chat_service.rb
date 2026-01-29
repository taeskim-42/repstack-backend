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
  # Tool Use Processing
  # ============================================

  def process_with_tools
    response = AiTrainer::LlmGateway.chat(
      prompt: build_user_prompt,
      task: :general_chat,
      system: system_prompt,
      tools: available_tools
    )

    return error_response("AI 응답 실패") unless response[:success]

    # Check if LLM called a tool
    if response[:tool_use]
      execute_tool(response[:tool_use])
    else
      # No tool called - use RAG for general chat
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
    level = user.level || 1

    <<~SYSTEM
      당신은 전문 피트니스 AI 트레이너입니다.

      ## 사용자 정보
      - 레벨: #{level} (#{tier})
      - 이름: #{user.name || '회원'}

      ## 규칙
      1. 루틴 생성/수정 요청이면 적절한 tool을 사용하세요
      2. 운동 기록 요청이면 record_exercise tool을 사용하세요
      3. 일반 질문이나 대화는 tool 없이 직접 답변하세요
      4. 친근하고 격려하는 톤으로 대화하세요
      5. 한국어로 응답하세요
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
    when "record_exercise"
      handle_record_exercise(input)
    when "replace_exercise"
      handle_replace_exercise(input)
    when "add_exercise"
      handle_add_exercise(input)
    when "regenerate_routine"
      handle_regenerate_routine(input)
    else
      error_response("알 수 없는 작업입니다: #{tool_name}")
    end
  end

  # ============================================
  # Tool Handlers
  # ============================================

  def handle_generate_routine(input)
    unless user.level.present?
      return error_response("먼저 간단한 체력 테스트를 완료해주세요! 그래야 맞춤 루틴을 만들 수 있어요.")
    end

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

    success_response(
      message: format_routine_message(routine),
      intent: "GENERATE_ROUTINE",
      data: { routine: routine }
    )
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
        data: { records: [record_item] }
      )
    else
      error_response(result[:error] || "기록 저장에 실패했어요.")
    end
  end

  def handle_replace_exercise(input)
    routine = current_routine
    return error_response("수정할 루틴을 찾을 수 없어요.") unless routine

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
      instructions: replacement[:instructions],
      weight_suggestion: replacement[:weight_guide]
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
    return error_response("완료된 루틴에는 운동을 추가할 수 없어요.") if routine.is_completed

    final_order = (routine.routine_exercises.maximum(:order_index) || -1) + 1

    exercise = routine.routine_exercises.create!(
      exercise_name: input["exercise_name"],
      order_index: final_order,
      sets: input["sets"] || 3,
      reps: input["reps"] || 10,
      target_muscle: infer_target_muscle(input["exercise_name"]),
      rest_duration_seconds: 60
    )

    success_response(
      message: "**#{input['exercise_name']}** #{exercise.sets}세트 x #{exercise.reps}회를 추가했어요! 💪",
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
        instructions: ex[:instructions],
        weight_suggestion: ex[:weight_description]
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

  # ============================================
  # General Chat with RAG
  # ============================================

  def handle_general_chat_with_rag
    result = AiTrainer::ChatService.general_chat(
      user: user,
      message: message,
      session_id: session_id
    )

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

    prompt = <<~PROMPT
      새로 온보딩을 완료한 사용자에게 첫 인사를 해주세요.

      ## 사용자 정보
      - 이름: #{user.name || '회원'}
      - 레벨: #{level} (#{tier_korean(tier)})
      - 목표: #{goal}
      - 키: #{profile&.height}cm
      - 체중: #{profile&.weight}kg

      ## 응답 규칙
      1. 환영 인사 (이름 포함)
      2. 프로필 정보 간단히 확인해줌
      3. 첫 운동 루틴을 만들어볼지 제안
      4. 친근하고 격려하는 톤
      5. 2-3문장으로 간결하게
      6. 이모지 적절히 사용
    PROMPT

    response = AiTrainer::LlmGateway.chat(
      prompt: prompt,
      task: :welcome_message,
      system: "당신은 친근한 피트니스 AI 트레이너입니다. 한국어로 응답하세요."
    )

    welcome_text = if response[:success]
      response[:content]
    else
      default_welcome_message(profile)
    end

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
        suggestions: [
          "오늘 루틴 만들어줘",
          "내 레벨에 맞는 운동 추천해줘",
          "운동 어떻게 시작하면 좋을까?"
        ]
      }
    )
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

  # ============================================
  # Level Assessment (Special Flow)
  # ============================================

  def needs_level_assessment?
    AiTrainer::LevelAssessmentService.needs_assessment?(user)
  end

  def handle_level_assessment
    result = AiTrainer::LevelAssessmentService.assess(user: user, message: message)

    if result[:success]
      success_response(
        message: result[:message],
        intent: "LEVEL_ASSESSMENT",
        data: {
          is_complete: result[:is_complete],
          assessment: result[:assessment]
        }
      )
    else
      error_response(result[:error] || "수준 파악에 실패했어요.")
    end
  end

  # ============================================
  # Helpers
  # ============================================

  def current_routine
    @current_routine ||= user.workout_routines.find_by(id: routine_id)
  end

  def find_exercise_in_routine(routine, exercise_name)
    return nil unless exercise_name.present?

    name_lower = exercise_name.downcase.gsub(/\s+/, "")

    routine.routine_exercises.find do |ex|
      ex.exercise_name.downcase.gsub(/\s+/, "").include?(name_lower) ||
        name_lower.include?(ex.exercise_name.downcase.gsub(/\s+/, ""))
    end
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
    {
      success: true,
      exercise_name: data["exercise_name"],
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

  def format_routine_message(routine)
    msg = "오늘의 루틴을 준비했어요! 💪\n\n"
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

  def success_response(message:, intent:, data:)
    { success: true, message: message, intent: intent, data: data, error: nil }
  end

  def error_response(error_message)
    { success: false, message: nil, intent: nil, data: nil, error: error_message }
  end
end
