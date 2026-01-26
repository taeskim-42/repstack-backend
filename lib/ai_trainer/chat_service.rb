# frozen_string_literal: true

require_relative "constants"
require_relative "llm_gateway"

module AiTrainer
  # Handles general fitness-related chat using LLM Gateway
  # Routes to cost-efficient models for conversational queries
  # Enhanced with RAG (Retrieval Augmented Generation) from YouTube fitness knowledge
  class ChatService
    include Constants

    class << self
      def general_chat(user:, message:)
        new(user: user).general_chat(message)
      end
    end

    def initialize(user:)
      @user = user
    end

    def general_chat(message)
      # Retrieve relevant knowledge from YouTube fitness channels
      knowledge_context = retrieve_knowledge(message)

      prompt = build_prompt(message, knowledge_context)
      response = LlmGateway.chat(prompt: prompt, task: :general_chat)

      if response[:success]
        {
          success: true,
          message: response[:content].strip,
          model: response[:model],
          knowledge_used: knowledge_context[:used]
        }
      else
        { success: false, message: "죄송해요, 잠시 문제가 생겼어요. 다시 질문해주세요!" }
      end
    rescue StandardError => e
      Rails.logger.error("ChatService error: #{e.message}")
      { success: false, message: "죄송해요, 잠시 문제가 생겼어요. 다시 질문해주세요!" }
    end

    private

    attr_reader :user

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

      all_results = []

      # Search each keyword
      keywords.first(5).each do |keyword|
        results = RagSearchService.search(keyword, limit: 2)
        all_results.concat(results)
      end

      # Deduplicate and limit
      all_results.uniq { |r| r[:id] }.first(5)
    end

    def build_prompt(message, knowledge_context)
      user_level = user.user_profile&.numeric_level || 1
      user_tier = Constants.tier_for_level(user_level)

      prompt_parts = []

      prompt_parts << <<~INTRO
        당신은 친근한 AI 피트니스 트레이너입니다. 사용자의 질문에 짧고 도움되게 답변하세요.

        ## 사용자 정보
        - 레벨: #{user_level}/8 (#{user_tier})
        - 이름: #{user.name || '회원'}
      INTRO

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

        ## 사용자 질문
        "#{message}"

        위 질문에 친근하게 답변하세요. JSON 형식 없이 자연스러운 대화체로 답변합니다.
      RULES

      prompt_parts.join("\n")
    end
  end
end
