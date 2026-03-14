# frozen_string_literal: true

# ChatService: Tool Use based AI trainer
# LLM decides which tool to use based on user message
#
# Decomposed into concerns:
#   ChatPromptBuilder    - system prompt, user prompt, tools, conversation context
#   ChatToolHandlers     - tool dispatch + all handle_* methods
#   ChatOnboarding       - daily greeting, welcome, level assessment, today-routine
#   ChatRoutineFormatter - format_*, build_long_term_plan, save_routine_to_db
#   ChatMessageHelpers   - suggestions, caching, response builders, routine lookup
class ChatService
  include ChatPromptBuilder
  include ChatToolHandlers
  include ChatOnboarding
  include ChatRoutineFormatter
  include ChatMessageHelpers

  class << self
    def process(user:, message:, routine_id: nil, session_id: nil)
      # Structured commands bypass Agent Service — handle directly in Ruby
      if message.strip.start_with?("/") && STRUCTURED_COMMANDS.key?(message.strip)
        return new(user: user, message: message.strip, routine_id: routine_id, session_id: session_id).process
      end

      # Route to Agent Service if available and user has access
      if use_agent_service?(user)
        result = AgentBridge.process(
          user: user,
          message: message,
          routine_id: routine_id,
          session_id: session_id
        )
        return result if result
      end

      # Legacy stateless processing
      new(user: user, message: message, routine_id: routine_id, session_id: session_id).process
    end

    private

    def use_agent_service?(user)
      return false unless AgentBridge.available?
      return false unless ENV["AGENT_SERVICE_ENABLED"] == "true"
      return false unless user.user_profile&.onboarding_completed_at.present?

      true
    end
  end

  def initialize(user:, message:, routine_id: nil, session_id: nil)
    @user = user
    @message = message.strip
    @routine_id = routine_id
    @session_id = session_id
  end

  # Structured command mapping: iOS sends language-independent commands
  STRUCTURED_COMMANDS = {
    "/start_workout" => :handle_start_workout_command,
    "/end_workout" => :handle_end_workout_command,
    "/workout_complete" => :handle_workout_complete_command,
    "/check_condition" => :handle_check_condition_command,
    "/generate_routine" => :handle_generate_routine_command
  }.freeze

  def process
    user.reload

    # Structured command routing
    if message.start_with?("/")
      handler = STRUCTURED_COMMANDS[message]
      return send(handler) if handler
    end

    # Pre-load recent messages once
    load_recent_messages

    # Trigger memory extraction for previous session if session changed
    detect_and_trigger_memory_extraction

    return handle_daily_greeting if needs_daily_greeting?
    return handle_show_today_routine if wants_today_routine?
    return handle_welcome_message if needs_welcome_message?
    return handle_level_assessment if needs_level_assessment?

    # Instant routine shortcut — skip LLM tool selection entirely
    if (instant = try_instant_routine_retrieval)
      return instant
    end

    process_with_tools
  rescue StandardError => e
    Rails.logger.error("ChatService error: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
    error_response("처리 중 오류가 발생했습니다: #{e.message}")
  end

  private

  attr_reader :user, :message, :routine_id, :session_id

  def process_with_tools
    cached_answer = get_cached_response
    if cached_answer
      return success_response(
        message: cached_answer,
        intent: "CACHED_RESPONSE",
        data: {
          cached: true,
          suggestions: [ "오늘 루틴 만들어줘", "내 운동 계획 알려줘", "더 궁금한 거 있어" ]
        }
      )
    end

    Rails.logger.info("[ChatService] Processing message: #{message}")
    Rails.logger.info("[ChatService] Available tools: #{available_tools.map { |t| t[:name] }.join(', ')}")

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

    if response[:tool_use]
      Rails.logger.info("[ChatService] Tool called: #{response[:tool_use][:name]}")
      execute_tool(response[:tool_use])
    else
      Rails.logger.info("[ChatService] No tool called, using RAG for general chat")
      handle_general_chat_with_rag
    end
  end

  # Detect session change and trigger memory extraction for previous session
  def detect_and_trigger_memory_extraction
    return if session_id.blank?

    last_message = @recent_messages.last
    return unless last_message

    if last_message.session_id.present? && last_message.session_id != session_id
      ConversationMemoryJob.perform_async(user.id, last_message.session_id)
    end
  rescue StandardError => e
    Rails.logger.warn("[ChatService] Memory extraction trigger failed: #{e.message}")
  end
end
