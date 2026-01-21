# frozen_string_literal: true

require_relative "constants"

module AiTrainer
  # Analyzes user condition from natural language text
  # Uses Claude API for intelligent interpretation
  class ConditionService
    include Constants

    API_URL = "https://api.anthropic.com/v1/messages"
    MODEL = "claude-sonnet-4-20250514"
    MAX_TOKENS = 1024

    class << self
      def analyze_from_text(user:, text:)
        new(user: user).analyze_from_text(text)
      end
    end

    def initialize(user:)
      @user = user
    end

    def analyze_from_text(text)
      return mock_response unless api_configured?

      prompt = build_prompt(text)
      response = call_claude_api(prompt)
      parse_response(response, text)
    rescue StandardError => e
      Rails.logger.error("ConditionService error: #{e.message}")
      { success: false, error: "컨디션 분석 실패: #{e.message}" }
    end

    private

    attr_reader :user

    def api_configured?
      ENV["ANTHROPIC_API_KEY"].present?
    end

    def build_prompt(text)
      <<~PROMPT
        당신은 전문 피트니스 트레이너입니다. 사용자가 말한 컨디션 상태를 분석하세요.

        사용자 입력: "#{text}"

        아래 항목들을 0-5 점수로 평가하고 운동 조언을 제공하세요:
        - energy_level: 에너지 수준 (5=최상, 1=최하)
        - stress_level: 스트레스 (5=매우 높음, 1=없음) - 역수 처리 필요
        - sleep_quality: 수면 품질 (5=최상, 1=최하)
        - motivation: 운동 의욕 (5=최상, 1=최하)
        - soreness: 근육통 (5=매우 심함, 1=없음) - 역수 처리 필요

        반드시 아래 JSON 형식으로만 응답하세요:
        ```json
        {
          "parsed_condition": {
            "energy_level": 3,
            "stress_level": 2,
            "sleep_quality": 4,
            "motivation": 3,
            "soreness": 1
          },
          "overall_score": 75,
          "status": "good",
          "message": "사용자에게 전달할 친근한 응답 메시지",
          "adaptations": ["운동 강도 조절 제안", "특정 운동 권장/비권장"],
          "recommendations": ["일반적인 권장사항", "회복 관련 조언"]
        }
        ```

        status 값: "excellent" (90+), "good" (70-89), "fair" (50-69), "poor" (49 이하)
      PROMPT
    end

    def call_claude_api(prompt)
      uri = URI(API_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["x-api-key"] = ENV["ANTHROPIC_API_KEY"]
      request["anthropic-version"] = "2023-06-01"

      request.body = {
        model: MODEL,
        max_tokens: MAX_TOKENS,
        messages: [{ role: "user", content: prompt }]
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

    def parse_response(response_text, original_text)
      json_str = extract_json(response_text)
      data = JSON.parse(json_str)

      # Save condition log
      save_condition_log(data["parsed_condition"])

      {
        success: true,
        score: data["overall_score"],
        status: data["status"],
        message: data["message"],
        adaptations: data["adaptations"] || [],
        recommendations: data["recommendations"] || [],
        parsed_condition: data["parsed_condition"]
      }
    rescue JSON::ParserError => e
      Rails.logger.error("ConditionService JSON parse error: #{e.message}")
      { success: false, error: "응답 파싱 실패" }
    end

    def extract_json(text)
      if text =~ /```(?:json)?\s*(\{.*?\})\s*```/m
        Regexp.last_match(1)
      elsif text.include?("{")
        start_idx = text.index("{")
        end_idx = text.rindex("}")
        text[start_idx..end_idx] if start_idx && end_idx
      else
        text
      end
    end

    def save_condition_log(parsed_condition)
      return unless parsed_condition

      user.condition_logs.create!(
        date: Date.current,
        energy_level: parsed_condition["energy_level"] || 3,
        stress_level: parsed_condition["stress_level"] || 3,
        sleep_quality: parsed_condition["sleep_quality"] || 3,
        motivation: parsed_condition["motivation"] || 3,
        soreness: {},
        available_time: 60,
        notes: "Chat에서 입력"
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("ConditionService: Failed to save condition log: #{e.message}")
    end

    def mock_response
      {
        success: true,
        score: 70,
        status: "good",
        message: "컨디션을 확인했어요! 오늘도 화이팅! 💪",
        adaptations: ["평소 강도로 운동 가능"],
        recommendations: ["충분한 수분 섭취", "운동 전 워밍업 필수"]
      }
    end
  end
end
