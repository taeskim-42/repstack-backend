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

    # 2. Exercise record pattern (regex - 확실한 것만)
    if matches_record_pattern?
      return handle_record_exercise
    end

    # 3. Everything else → RAG + LLM (Notion AI style)
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
