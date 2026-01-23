# frozen_string_literal: true

require_relative "constants"
require_relative "llm_gateway"

module AiTrainer
  # Handles general fitness-related chat using LLM Gateway
  # Routes to cost-efficient models for conversational queries
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
      prompt = build_prompt(message)
      response = LlmGateway.chat(prompt: prompt, task: :general_chat)

      if response[:success]
        {
          success: true,
          message: response[:content].strip,
          model: response[:model]
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

    def build_prompt(message)
      user_level = user.user_profile&.numeric_level || 1
      user_tier = Constants.tier_for_level(user_level)

      <<~PROMPT
        당신은 친근한 AI 피트니스 트레이너입니다. 사용자의 질문에 짧고 도움되게 답변하세요.

        ## 사용자 정보
        - 레벨: #{user_level}/8 (#{user_tier})
        - 이름: #{user.name || '회원'}

        ## 규칙
        1. 운동/피트니스 관련 질문에만 답변하세요
        2. 친근하고 격려하는 톤을 유지하세요
        3. 답변은 2-3문장으로 간결하게
        4. 이모지를 적절히 사용하세요
        5. 사용자 레벨에 맞는 조언을 제공하세요

        ## 사용자 질문
        "#{message}"

        위 질문에 친근하게 답변하세요. JSON 형식 없이 자연스러운 대화체로 답변합니다.
      PROMPT
    end
  end
end
