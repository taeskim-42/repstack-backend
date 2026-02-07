# frozen_string_literal: true

require_relative "constants"
require_relative "llm_gateway"

module AiTrainer
  # Handles general fitness-related chat using LLM Gateway
  # Routes to cost-efficient models for conversational queries
  # Enhanced with RAG (Retrieval Augmented Generation) from YouTube fitness knowledge
  # Uses Prompt Caching for cost-efficient conversation history
  class ChatService
    include Constants

    HISTORY_LIMIT = 30  # Max messages to include in context
    CACHE_LIMIT = 3     # Messages to cache (Anthropic allows max 4 total, 1 for system prompt)

    class << self
      def general_chat(user:, message:, session_id: nil)
        new(user: user, session_id: session_id).general_chat(message)
      end
    end

    def initialize(user:, session_id: nil)
      @user = user
      @session_id = session_id || generate_session_id
    end

    def general_chat(message)
      # Save user message
      save_message(role: "user", content: message)

      # Retrieve relevant knowledge from YouTube fitness channels
      knowledge_context = retrieve_knowledge(message)

      # Build messages with conversation history (with caching)
      messages = build_messages_with_history(message)

      # Build system prompt
      system_prompt = build_system_prompt(knowledge_context)

      # Call LLM with conversation history and caching
      response = LlmGateway.chat(
        prompt: message,
        task: :general_chat,
        messages: messages,
        system: system_prompt,
        cache_system: true
      )

      if response[:success]
        assistant_message = response[:content].strip

        # Save assistant response
        save_message(role: "assistant", content: assistant_message)

        {
          success: true,
          message: assistant_message,
          model: response[:model],
          knowledge_used: knowledge_context[:used],
          session_id: @session_id,
          cache_stats: {
            cache_read_tokens: response.dig(:usage, :cache_read_input_tokens),
            cache_creation_tokens: response.dig(:usage, :cache_creation_input_tokens)
          }
        }
      else
        { success: false, message: "죄송해요, 잠시 문제가 생겼어요. 다시 질문해주세요!" }
      end
    rescue StandardError => e
      Rails.logger.error("ChatService error: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      { success: false, message: "죄송해요, 잠시 문제가 생겼어요. 다시 질문해주세요!" }
    end

    private

    attr_reader :user, :session_id

    def save_message(role:, content:)
      ChatMessage.create!(
        user: user,
        role: role,
        content: content,
        session_id: @session_id
      )
    rescue StandardError => e
      Rails.logger.warn("Failed to save chat message: #{e.message}")
    end

    def build_messages_with_history(new_message)
      # Get recent conversation history
      history = ChatMessage.recent_for_user(
        user.id,
        limit: HISTORY_LIMIT,
        session_id: @session_id
      )

      messages = []

      # Add history with caching on older messages
      history.each_with_index do |msg, idx|
        # Cache older messages (not the last 2 which change frequently)
        should_cache = idx < [history.length - 2, CACHE_LIMIT].min
        messages << msg.to_api_format(cache: should_cache)
      end

      messages
    end

    def generate_session_id
      # Session lasts for 30 minutes of inactivity
      last_message = ChatMessage.where(user_id: user.id).order(created_at: :desc).first

      if last_message && last_message.created_at > 30.minutes.ago
        last_message.session_id
      else
        # New session — trigger memory extraction for previous session
        if last_message&.session_id.present?
          ConversationMemoryJob.perform_async(user.id, last_message.session_id)
        end

        "session_#{user.id}_#{Time.current.to_i}"
      end
    end

    def retrieve_knowledge(message)
      # Extract keywords from message and search RAG
      keywords = extract_keywords(message)
      knowledge_chunks = search_with_keywords(keywords)

      if knowledge_chunks.any?
        {
          used: true,
          prompt: RagSearchService.build_context_prompt(knowledge_chunks),
          sources: knowledge_chunks.map { |c| c[:source] }.compact
        }
      else
        { used: false, prompt: "", sources: [] }
      end
    rescue StandardError => e
      Rails.logger.warn("RAG search failed: #{e.message}")
      { used: false, prompt: "", sources: [] }
    end

    def build_memory_context
      ConversationMemoryService.format_context(user)
    end

    def extract_keywords(message)
      # Remove common Korean particles and extract meaningful words
      stopwords = %w[은 는 이 가 을 를 의 에 에서 으로 로 와 과 하고 이고 라고 뭐라고 뭐 무엇 어떻게 어떤 왜 언제 좀 잘 더]
      words = message.gsub(/[?!.,]/, "").split(/\s+/)

      keywords = []

      words.each do |word|
        next if word.length < 2

        # Add original word
        keywords << word

        # Try removing common suffixes
        stopwords.each do |sw|
          if word.end_with?(sw) && word.length > sw.length + 1
            keywords << word.chomp(sw)
          end
        end
      end

      keywords.uniq.reject { |w| w.length < 2 }
    end

    def search_with_keywords(keywords)
      return [] if keywords.empty?

      RagSearchService.batch_search(keywords, limit: 5)
    end

    # Build system prompt for conversation (cached for efficiency)
    def build_system_prompt(knowledge_context)
      user_level = user.user_profile&.numeric_level || 1
      user_tier = Constants.tier_for_level(user_level)

      prompt_parts = []

      prompt_parts << <<~INTRO
        당신은 친근한 AI 피트니스 트레이너입니다. 사용자의 질문에 짧고 도움되게 답변하세요.

        ## 사용자 정보
        - 레벨: #{user_level}/8 (#{user_tier})
        - 이름: #{user.name || '회원'}
      INTRO

      # Inject conversation memory
      mem_ctx = build_memory_context
      prompt_parts << mem_ctx if mem_ctx.present?

      # Add RAG knowledge if available
      if knowledge_context[:used] && knowledge_context[:prompt].present?
        prompt_parts << knowledge_context[:prompt]
      end

      prompt_parts << <<~RULES
        ## 규칙
        1. 당신은 운동 전문 AI 트레이너입니다
        2. 운동 관련 질문에는 전문적으로 답변하세요
        3. 운동 외 질문에는 짧게 답하고, 자연스럽게 운동/건강 주제로 대화를 유도하세요
           예시: "피자 먹고 싶어" → "피자 맛있죠! 🍕 운동 후에 드시면 죄책감 없이 즐길 수 있어요. 오늘 루틴은 확인하셨나요?"
           예시: "주식 추천해줘" → "저는 운동 전문이라 주식은 잘 모르겠어요 😅 대신 오늘 운동 계획 세워드릴까요?"
        4. 친근하고 격려하는 톤을 유지하세요
        5. 답변은 2-3문장으로 간결하게
        6. 이모지를 적절히 사용하세요
        7. 사용자 레벨에 맞는 조언을 제공하세요
        8. 이전 대화 내용을 참고하여 맥락에 맞게 답변하세요

        ## ⚠️ 매우 중요: 맥락 이해
        - 당신이 질문을 했다면, 사용자의 다음 답변은 **그 질문에 대한 답변**입니다
        - 예시:
          - 당신: "오늘 컨디션은 어떠세요?" → 사용자: "아주 좋아" → 이것은 **컨디션이 좋다는 답변**입니다
          - 당신: "오늘 운동 계획 있으세요?" → 사용자: "네" → 이것은 **운동 계획이 있다는 답변**입니다
        - 사용자가 짧게 답변해도 (예: "좋아", "네", "아니요", "피곤해") 직전 대화 맥락에서 의미를 파악하세요
        - 맥락 없이 단어만 보고 엉뚱한 해석을 하지 마세요

        ## 🔘 suggestions (매우 중요!)
        - 답변 마지막에 **반드시** 다음 형식으로 사용자가 탭할 수 있는 선택지를 포함하세요:
          suggestions: ["선택지1", "선택지2", "선택지3"]
        - 선택지는 현재 대화 맥락에 맞는 자연스러운 후속 질문/행동이어야 합니다
        - 2~4개, 각 15자 이내로 짧게
        - 예시:
          - 벤치프레스 폼 설명 후 → suggestions: ["다른 폼도 알려줘", "오늘 루틴 만들어줘", "무게 추천해줘"]
          - 영양 조언 후 → suggestions: ["식단 더 알려줘", "오늘 루틴 만들어줘", "단백질 얼마나 먹어야 해"]
          - 일반 대화 후 → suggestions: ["오늘 운동 뭐해", "운동 계획 알려줘", "더 궁금한 거 있어"]

        위 규칙에 따라 친근하게 답변하세요. JSON 형식 없이 자연스러운 대화체로 답변하되, 마지막에 suggestions 행을 꼭 추가하세요.
      RULES

      prompt_parts.join("\n")
    end
  end
end
