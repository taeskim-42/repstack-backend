# frozen_string_literal: true

require_relative "constants"

module AiTrainer
  # Handles general fitness-related chat using Claude Haiku
  # Cost-efficient for conversational queries
  class ChatService
    include Constants

    API_URL = "https://api.anthropic.com/v1/messages"
    # Use Haiku for cost efficiency (~$0.002 per request)
    MODEL = "claude-3-5-haiku-20241022"
    MAX_TOKENS = 512

    class << self
      def general_chat(user:, message:)
        new(user: user).general_chat(message)
      end
    end

    def initialize(user:)
      @user = user
    end

    def general_chat(message)
      return mock_response(message) unless api_configured?

      prompt = build_prompt(message)
      response = call_claude_api(prompt)
      parse_response(response)
    rescue StandardError => e
      Rails.logger.error("ChatService error: #{e.message}")
      { success: false, message: "죄송해요, 잠시 문제가 생겼어요. 다시 질문해주세요!" }
    end

    private

    attr_reader :user

    def api_configured?
      ENV["ANTHROPIC_API_KEY"].present?
    end

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

    def call_claude_api(prompt)
      uri = URI(API_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 15

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["x-api-key"] = ENV["ANTHROPIC_API_KEY"]
      request["anthropic-version"] = "2023-06-01"

      request.body = {
        model: MODEL,
        max_tokens: MAX_TOKENS,
        messages: [ { role: "user", content: prompt } ]
      }.to_json

      response = http.request(request)

      if response.code.to_i == 200
        data = JSON.parse(response.body)
        data.dig("content", 0, "text")
      else
        Rails.logger.error("Claude API error: #{response.code} - #{response.body}")
        raise "Claude API returned #{response.code}"
      end
    end

    def parse_response(response_text)
      {
        success: true,
        message: response_text.strip
      }
    end

    def mock_response(message)
      responses = [
        "좋은 질문이에요! 운동할 때 가장 중요한 건 꾸준함이에요. 💪",
        "화이팅! 오늘도 열심히 운동해봐요! 🏋️",
        "그 부분이 궁금하셨군요! 트레이너로서 최선을 다해 도와드릴게요. 😊"
      ]
      {
        success: true,
        message: responses.sample
      }
    end
  end
end
