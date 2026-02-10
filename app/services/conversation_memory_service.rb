# frozen_string_literal: true

# Extracts and stores conversation memories from completed chat sessions.
# Two-tier memory: session summaries (last 3) + key facts (max 20).
# Stored in user_profile.fitness_factors JSONB.
class ConversationMemoryService
  MAX_KEY_FACTS = 50
  MAX_SESSION_SUMMARIES = 10
  MIN_USER_MESSAGES = 2
  FACT_CATEGORIES = %w[injury goal preference personal habit progress milestone].freeze

  class << self
    def extract(user:, session_id:)
      new(user: user, session_id: session_id).extract
    end

    # Build formatted memory context string from user's stored memories.
    # Returns nil if no memories exist.
    def format_context(user)
      factors = user.user_profile&.fitness_factors
      return nil if factors.blank?

      parts = []

      memories = factors["trainer_memories"]
      if memories.present?
        facts = memories.map { |m| "- #{m['fact']} (#{m['category']}, #{m['date']})" }.join("\n")
        parts << "## 기억하고 있는 사항\n#{facts}"
      end

      summaries = factors["session_summaries"]
      if summaries.present?
        lines = summaries.map { |s| "- [#{s['date']}] #{s['summary']}" }.join("\n")
        parts << "## 최근 대화 요약\n#{lines}"
      end

      personality = factors["personality_profile"]
      if personality.present?
        parts << "## 사용자 성격/대화 스타일\n#{personality}"
      end

      timeline = factors["progress_timeline"]
      if timeline.present? && timeline.any?
        milestones = timeline.last(10).map { |t| "- [#{t['date']}] #{t['event']} (#{t['type']})" }.join("\n")
        parts << "## 주요 이정표\n#{milestones}"
      end

      parts.any? ? parts.join("\n\n") : nil
    rescue StandardError => e
      Rails.logger.warn("[ConversationMemory] format_context failed: #{e.message}")
      nil
    end
  end

  def initialize(user:, session_id:)
    @user = user
    @session_id = session_id
  end

  def extract
    profile = user.user_profile
    return unless profile

    # Skip if already processed
    factors = profile.fitness_factors || {}
    return if factors.dig("last_memory_session_id") == session_id

    # Get session messages
    messages = ChatMessage.for_session(session_id)
                          .where(user_id: user.id)
                          .chronological

    user_messages = messages.select { |m| m.role == "user" }
    return if user_messages.size < MIN_USER_MESSAGES

    # Build conversation text (truncate each message)
    conversation_text = messages.map do |m|
      role = m.role == "user" ? "사용자" : "트레이너"
      "#{role}: #{m.content.to_s.truncate(200)}"
    end.join("\n")

    # Call LLM for extraction
    result = extract_from_llm(conversation_text)
    return unless result

    # Update fitness_factors
    update_memories(profile, factors, result)

    Rails.logger.info("[ConversationMemory] Extracted #{result[:key_facts]&.size || 0} facts, summary for session #{session_id}")
  rescue StandardError => e
    Rails.logger.error("[ConversationMemory] Error: #{e.message}")
    nil
  end

  private

  attr_reader :user, :session_id

  def extract_from_llm(conversation_text)
    response = AiTrainer::LlmGateway.chat(
      prompt: build_extraction_prompt(conversation_text),
      task: :memory_extraction,
      cache_system: false
    )

    return unless response[:success] && response[:content].present?

    parse_extraction_response(response[:content])
  end

  def build_extraction_prompt(conversation_text)
    <<~PROMPT
      다음 트레이너-사용자 대화에서 두 가지를 추출해주세요:

      1. key_facts: 사용자 개인에 관한 중요 사실
         - 일시적 상태("오늘 피곤해")는 제외, 지속적 사실만 포함
         - category: injury(부상/통증), goal(목표), preference(선호), personal(개인정보), habit(운동 습관), progress(성장/변화), milestone(PR/레벨업 등 이정표)
      2. summary: 대화 전체 요약 (100자 이내, 한국어)
      3. personality_notes: 사용자의 대화 스타일/성격 관찰 (있으면, 없으면 null)

      대화:
      #{conversation_text}

      반드시 아래 JSON 형식으로만 답변하세요. 추출할 사실이 없으면 빈 배열:
      {"key_facts":[{"fact":"내용","category":"injury|goal|preference|personal|habit|progress|milestone"}],"summary":"요약","personality_notes":"성격/대화 스타일 관찰 또는 null"}
    PROMPT
  end

  def parse_extraction_response(content)
    # Extract JSON from response (handle markdown code blocks)
    json_str = content.match(/\{.*\}/m)&.to_s
    return nil if json_str.blank?

    parsed = JSON.parse(json_str, symbolize_names: true)

    key_facts = parsed[:key_facts]
    summary = parsed[:summary]

    return nil if key_facts.nil? && summary.blank?

    { key_facts: Array(key_facts), summary: summary.to_s, personality_notes: parsed[:personality_notes] }
  rescue JSON::ParserError => e
    Rails.logger.warn("[ConversationMemory] JSON parse error: #{e.message}")
    nil
  end

  def update_memories(profile, factors, result)
    today = Time.current.strftime("%Y-%m-%d")

    # Update key facts (FIFO, deduplicate, max 20)
    existing_facts = factors["trainer_memories"] || []
    new_facts = result[:key_facts].map do |f|
      { "fact" => f[:fact], "category" => f[:category], "date" => today }
    end

    # Deduplicate by fact content
    merged = merge_facts(existing_facts, new_facts)
    factors["trainer_memories"] = merged.last(MAX_KEY_FACTS)

    # Update session summaries (keep last 3)
    summaries = factors["session_summaries"] || []
    if result[:summary].present?
      summaries << {
        "date" => today,
        "summary" => result[:summary],
        "session_id" => session_id
      }
      factors["session_summaries"] = summaries.last(MAX_SESSION_SUMMARIES)
    end

    # Update personality profile (append observations)
    if result[:personality_notes].present?
      existing_personality = factors["personality_profile"] || ""
      factors["personality_profile"] = [existing_personality, result[:personality_notes]]
                                        .reject(&:blank?)
                                        .join(" | ")
                                        .truncate(500)
    end

    # Mark as processed
    factors["last_memory_session_id"] = session_id

    profile.update!(fitness_factors: factors)
  end

  def merge_facts(existing, new_facts)
    all = existing + new_facts

    # Deduplicate: if two facts are very similar, keep the newer one
    all.uniq { |f| f["fact"].to_s.gsub(/\s+/, "").downcase }
  end
end
