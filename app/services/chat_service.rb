# frozen_string_literal: true

# ChatService: Tool Use based AI trainer
# LLM decides which tool to use based on user message
#
# Decomposed into concerns:
#   ChatPromptBuilder    - system prompt, user prompt, tools, conversation context
#   ChatToolHandlers     - tool dispatch + all handle_* methods
#   ChatOnboarding       - daily greeting, welcome, level assessment, today-routine
#   ChatRoutineFormatter - format_*, build_long_term_plan, save_routine_to_db
class ChatService
  include ChatPromptBuilder
  include ChatToolHandlers
  include ChatOnboarding
  include ChatRoutineFormatter

  class << self
    def process(user:, message:, routine_id: nil, session_id: nil)
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

      # TODO: Add user tier check (e.g., premium-only)
      true
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

    # Pre-load recent messages once (used by memory extraction, context summary, conversation history)
    load_recent_messages

    # Trigger memory extraction for previous session if session changed
    detect_and_trigger_memory_extraction

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

    # 2.5. Instant routine shortcut — skip LLM tool selection entirely
    if (instant = try_instant_routine_retrieval)
      return instant
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

    ChatResponseCache.cache_response(question: message, answer: answer)
  rescue => e
    Rails.logger.error("[ChatService] Cache save error: #{e.message}")
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
        data: {
          cached: true,
          suggestions: [
            "오늘 루틴 만들어줘",
            "내 운동 계획 알려줘",
            "더 궁금한 거 있어"
          ]
        }
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

  # Detect session change and trigger memory extraction for previous session
  def detect_and_trigger_memory_extraction
    return if session_id.blank?

    last_message = @recent_messages.last
    return unless last_message

    # If the incoming session_id differs from the last message's session, extract from old session
    if last_message.session_id.present? && last_message.session_id != session_id
      ConversationMemoryJob.perform_async(user.id, last_message.session_id)
    end
  rescue StandardError => e
    Rails.logger.warn("[ChatService] Memory extraction trigger failed: #{e.message}")
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

  # Extract choice options from AI message for button display
  def extract_suggestions_from_message(message)
    return [] if message.blank?

    suggestions = []

    # Pattern 0: "suggestions:" followed by JSON array or "- [...]" format
    suggestions_pattern = /suggestions:\s*-?\s*\[([^\]]+)\]/i
    if message =~ suggestions_pattern
      raw = $1
      items = raw.scan(/"([^"]+)"/).flatten
      if items.length >= 2
        return items.first(4)
      end
    end

    # Pattern 1: Numbered emoji options (1️⃣, 2️⃣, 3️⃣)
    emoji_pattern = /([1-9]️⃣[^\n]+)/
    emoji_matches = message.scan(emoji_pattern).flatten
    if emoji_matches.length >= 2
      suggestions = emoji_matches.map do |match|
        match.gsub(/^[1-9]️⃣\s*/, "").strip
      end
      return suggestions.first(4) if suggestions.any?
    end

    # Pattern 2: "A? B?" format (Korean question options)
    question_pattern = /([가-힣a-zA-Z0-9]+)\?\s*([가-힣a-zA-Z0-9]+)\?/
    if message =~ question_pattern
      suggestions = [$1, $2]
      return suggestions if suggestions.length >= 2
    end

    # Pattern 3: "(A/B/C)" format
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
    numbered_pattern = /\d+\.\s*([^\d\n]+?)(?=\s*\d+\.|$)/
    numbered_matches = message.scan(numbered_pattern).flatten.map(&:strip).reject(&:blank?)
    if numbered_matches.length >= 2
      suggestions = numbered_matches.first(4)
      return suggestions
    end

    suggestions
  end

  # Strip "suggestions: ..." text from message so it doesn't show in chat
  # Handles various LLM output formats: unicode spaces, missing colon, hyphen prefix, etc.
  def strip_suggestions_text(message)
    return message if message.blank?

    cleaned = message.dup

    # Pattern 1: "suggestions: [...]" anywhere (with unicode spaces, optional colon/hyphen)
    # Covers: "suggestions: [...]", "suggestions - [...]", "suggestions[...]", "Suggestions: [...]"
    cleaned.gsub!(/[[:space:]]*suggestions\s*[:：\-]?\s*-?\s*\[.*?\]/mi, "")

    # Pattern 2: "suggestions:" followed by rest of message (no bracket, free-form text)
    cleaned.gsub!(/[[:space:]]*suggestions\s*[:：]\s*[^\[].*/mi, "")

    # Pattern 3: Trailing numbered lists that look like suggestions (1. A\n2. B\n3. C at end)
    cleaned.gsub!(/\n+(?:\d+[.)\-]\s*[^\n]+\n*){2,}\z/m, "")

    # Clean up orphaned markdown bold/italic markers left after stripping (e.g., trailing "**")
    cleaned.gsub!(/\s*\*{1,3}\s*\z/, "")

    # Clean up excessive trailing newlines
    cleaned.strip
  end

  def success_response(message:, intent:, data:)
    # Strip raw "suggestions: [...]" text that LLM may include in message
    clean_msg = strip_suggestions_text(message)

    # Strip markdown formatting — iOS app doesn't render markdown bold/headers
    # TODO: Remove this when iOS supports AttributedString markdown rendering
    clean_msg = clean_msg&.gsub(/\*\*([^*]*)\*\*/, '\1') # **bold** → bold
                         &.gsub(/^##\s+/, "")             # ## heading → heading
    { success: true, message: clean_msg, intent: intent, data: data, error: nil }
  end

  def error_response(error_message)
    { success: false, message: nil, intent: nil, data: nil, error: error_message }
  end
end
