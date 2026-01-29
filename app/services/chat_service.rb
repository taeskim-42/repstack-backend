# frozen_string_literal: true

# ChatService: Notion AI-style conversational trainer
# No intent classification - just RAG + LLM for natural conversation
class ChatService
  # Record patterns for exercise recording (regex only)
  RECORD_PATTERNS = [
    /(?<exercise>.+?)\s*(?<weight>\d+(?:\.\d+)?)\s*(?:kg|킬로|킬로그램)\s*(?<reps>\d+)\s*(?:회|개|번|reps?)/i,
    /(?<exercise>.+?)\s*(?<weight>\d+(?:\.\d+)?)\s*(?:kg|킬로)\s*(?<reps>\d+)\s*(?:회|개|번)\s*(?<sets>\d+)\s*세트/i,
    /(?<exercise>.+?)\s*(?<reps>\d+)\s*(?:회|개|번)\s*(?<sets>\d+)\s*세트/i,
    /(?<exercise>.+?)\s*(?<sets>\d+)\s*세트\s*(?<reps>\d+)\s*(?:회|개|번)/i,
    /(?<exercise>.+?)\s*(?<reps>\d+)\s*(?:회|개|번)/i
  ].freeze

  # Routine request patterns
  ROUTINE_KEYWORDS = %w[
    루틴 운동프로그램 운동루틴 오늘운동 프로그램
    workout routine program
  ].freeze

  ROUTINE_ACTION_KEYWORDS = %w[
    줘 만들어 생성 추천 알려 시작
    give make create recommend start
  ].freeze

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
    # 1. New user onboarding
    if needs_level_assessment?
      return handle_level_assessment
    end

    # 2. Routine generation request
    if wants_routine?
      return handle_routine_generation
    end

    # 3. Exercise record pattern (regex - 확실한 것만)
    if matches_record_pattern?
      return handle_record_exercise
    end

    # 4. Everything else → RAG + LLM (Notion AI style)
    handle_chat
  rescue StandardError => e
    Rails.logger.error("ChatService error: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
    error_response("처리 중 오류가 발생했습니다: #{e.message}")
  end

  private

  attr_reader :user, :message, :routine_id, :session_id

  # ============================================
  # Level Assessment (New User Onboarding)
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
  # Routine Generation
  # ============================================

  def wants_routine?
    msg = message.downcase
    has_routine_keyword = ROUTINE_KEYWORDS.any? { |kw| msg.include?(kw) }
    has_action_keyword = ROUTINE_ACTION_KEYWORDS.any? { |kw| msg.include?(kw) }

    # "루틴 줘", "오늘 운동 뭐해", "프로그램 만들어줘" 등
    has_routine_keyword && has_action_keyword
  end

  def handle_routine_generation
    # Check if user has completed level assessment
    unless user.level.present?
      return error_response("먼저 간단한 체력 테스트를 완료해주세요! 그래야 맞춤 루틴을 만들 수 있어요.")
    end

    # Get current day of week (1=Monday, 7=Sunday)
    day_of_week = Time.current.wday
    day_of_week = day_of_week == 0 ? 7 : day_of_week  # Convert Sunday from 0 to 7

    # Fetch recent feedbacks for personalization
    recent_feedbacks = user.workout_feedbacks
                           .order(created_at: :desc)
                           .limit(5)

    # Extract goal from message if present
    goal = extract_goal_from_message

    # Generate routine
    routine = AiTrainer.generate_routine(
      user: user,
      day_of_week: day_of_week,
      condition_inputs: {},
      recent_feedbacks: recent_feedbacks,
      goal: goal
    )

    if routine.is_a?(Hash) && routine[:success] == false
      return error_response(routine[:error] || "루틴 생성에 실패했어요.")
    end

    # Format response message
    response_message = format_routine_message(routine)

    success_response(
      message: response_message,
      intent: "GENERATE_ROUTINE",
      data: { routine: routine }
    )
  end

  def extract_goal_from_message
    # Extract training goal from message
    # e.g., "등 운동 루틴 줘" → "등"
    # e.g., "체중 감량 프로그램" → "체중 감량"
    goal_patterns = [
      /(.+?)\s*(?:운동|트레이닝)?\s*루틴/,
      /(.+?)\s*프로그램/,
      /(.+?)\s*(?:위주로|중심으로)/
    ]

    goal_patterns.each do |pattern|
      match = message.match(pattern)
      if match && match[1].present?
        goal = match[1].strip
        # Filter out action words
        return nil if ROUTINE_ACTION_KEYWORDS.include?(goal.downcase)
        return goal unless goal.length > 20  # Sanity check
      end
    end

    nil
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

    if exercises.length > 5
      msg += "• ... 외 #{exercises.length - 5}개\n"
    end

    msg += "\n운동 시작할 준비가 되면 알려주세요!"
    msg
  end

  # ============================================
  # Exercise Recording (Regex only)
  # ============================================

  def matches_record_pattern?
    RECORD_PATTERNS.any? { |pattern| message.match?(pattern) }
  end

  def handle_record_exercise
    parsed = parse_exercise_record
    return error_response("운동 기록을 파싱하지 못했어요. 예: '벤치프레스 60kg 8회'") unless parsed

    result = ChatRecordService.record_exercise(
      user: user,
      exercise_name: parsed[:exercise],
      weight: parsed[:weight],
      reps: parsed[:reps],
      sets: parsed[:sets] || 1
    )

    if result[:success]
      record_item = {
        exercise_name: parsed[:exercise],
        weight: parsed[:weight],
        reps: parsed[:reps],
        sets: parsed[:sets] || 1,
        recorded_at: Time.current.iso8601
      }

      success_response(
        message: format_record_message(parsed),
        intent: "RECORD_EXERCISE",
        data: { records: [record_item] }
      )
    else
      error_response(result[:error] || "기록 저장에 실패했어요.")
    end
  end

  def parse_exercise_record
    RECORD_PATTERNS.each do |pattern|
      match = message.match(pattern)
      next unless match

      return {
        exercise: match[:exercise].strip,
        weight: match.names.include?("weight") ? match[:weight].to_f : nil,
        reps: match[:reps].to_i,
        sets: match.names.include?("sets") ? match[:sets].to_i : 1
      }
    end
    nil
  end

  def format_record_message(parsed)
    parts = ["기록했어요! #{parsed[:exercise]}"]
    parts << "#{parsed[:weight]}kg" if parsed[:weight]
    parts << "#{parsed[:reps]}회"
    parts << "#{parsed[:sets]}세트" if parsed[:sets] && parsed[:sets] > 1
    parts.join(" ") + " 💪"
  end

  # ============================================
  # RAG + LLM Chat (Notion AI style)
  # ============================================

  def handle_chat
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
  # Response Helpers
  # ============================================

  def success_response(message:, intent:, data:)
    {
      success: true,
      message: message,
      intent: intent,
      data: data,
      error: nil
    }
  end

  def error_response(error_message)
    {
      success: false,
      message: nil,
      intent: nil,
      data: nil,
      error: error_message
    }
  end
end
