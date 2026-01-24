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
      # Extract potential exercise names and muscle groups from the message
      exercises = extract_exercises(message)
      muscle_groups = extract_muscle_groups(message)

      # Search for relevant knowledge
      knowledge_chunks = if exercises.any? || muscle_groups.any?
        RagSearchService.contextual_search(
          exercises: exercises,
          muscle_groups: muscle_groups,
          difficulty_level: user_difficulty_level,
          limit: 3
        )
      else
        # General keyword search
        RagSearchService.search(message, limit: 3)
      end

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

    def extract_exercises(message)
      # Common exercise names to detect
      exercise_patterns = {
        "벤치프레스" => "bench_press",
        "벤치" => "bench_press",
        "스쿼트" => "squat",
        "데드리프트" => "deadlift",
        "데드" => "deadlift",
        "풀업" => "pullup",
        "푸시업" => "pushup",
        "팔굽혀펴기" => "pushup",
        "런지" => "lunge",
        "숄더프레스" => "shoulder_press",
        "오버헤드프레스" => "overhead_press",
        "로우" => "row",
        "바벨로우" => "barbell_row",
        "렛풀다운" => "lat_pulldown",
        "레그프레스" => "leg_press",
        "레그컬" => "leg_curl"
      }

      message_lower = message.downcase
      exercise_patterns.select { |korean, _| message_lower.include?(korean) }.values.uniq
    end

    def extract_muscle_groups(message)
      muscle_patterns = {
        "가슴" => "chest",
        "어깨" => "shoulder",
        "등" => "back",
        "하체" => "legs",
        "다리" => "legs",
        "허벅지" => "legs",
        "이두" => "biceps",
        "삼두" => "triceps",
        "복근" => "abs",
        "코어" => "core"
      }

      message_lower = message.downcase
      muscle_patterns.select { |korean, _| message_lower.include?(korean) }.values.uniq
    end

    def user_difficulty_level
      level = user.user_profile&.numeric_level || 1
      case level
      when 1..2 then "beginner"
      when 3..5 then "intermediate"
      else "advanced"
      end
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
        1. 운동/피트니스 관련 질문에만 답변하세요
        2. 친근하고 격려하는 톤을 유지하세요
        3. 답변은 2-3문장으로 간결하게
        4. 이모지를 적절히 사용하세요
        5. 사용자 레벨에 맞는 조언을 제공하세요

        ## 사용자 질문
        "#{message}"

        위 질문에 친근하게 답변하세요. JSON 형식 없이 자연스러운 대화체로 답변합니다.
      RULES

      prompt_parts.join("\n")
    end
  end
end
