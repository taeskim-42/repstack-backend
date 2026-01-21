# frozen_string_literal: true

require_relative "constants"

module AiTrainer
  # Analyzes workout feedback from natural language text
  # Stores feedback for future routine personalization
  class FeedbackService
    include Constants

    API_URL = "https://api.anthropic.com/v1/messages"
    MODEL = "claude-sonnet-4-20250514"
    MAX_TOKENS = 1024

    class << self
      def analyze_from_text(user:, text:, routine_id: nil)
        new(user: user).analyze_from_text(text, routine_id: routine_id)
      end
    end

    def initialize(user:)
      @user = user
    end

    def analyze_from_text(text, routine_id: nil)
      return mock_response unless api_configured?

      prompt = build_prompt(text)
      response = call_claude_api(prompt)
      parse_and_save_response(response, text, routine_id)
    rescue StandardError => e
      Rails.logger.error("FeedbackService error: #{e.message}")
      { success: false, error: "피드백 분석 실패: #{e.message}" }
    end

    private

    attr_reader :user

    def api_configured?
      ENV["ANTHROPIC_API_KEY"].present?
    end

    def build_prompt(text)
      <<~PROMPT
        당신은 전문 피트니스 트레이너입니다. 사용자의 운동 피드백을 분석하세요.

        사용자 피드백: "#{text}"

        피드백을 분석하고 다음 루틴 생성에 반영할 정보를 추출하세요:
        1. 어떤 운동이 힘들었거나 쉬웠는지
        2. 통증이나 불편함이 있었는지
        3. 운동 강도/볼륨이 적절했는지
        4. 다음 루틴에 어떤 조정이 필요한지

        반드시 아래 JSON 형식으로만 응답하세요:
        ```json
        {
          "feedback_type": "difficulty|pain|preference|general",
          "rating": 3,
          "insights": ["분석된 인사이트1", "분석된 인사이트2"],
          "adaptations": ["다음 루틴 적용사항1", "다음 루틴 적용사항2"],
          "next_workout_recommendations": ["대체 운동 추천", "강도 조절 방향"],
          "affected_exercises": ["런지", "스쿼트"],
          "affected_muscles": ["legs", "core"],
          "message": "사용자에게 전달할 친근한 응답 메시지"
        }
        ```

        feedback_type 값:
        - "difficulty": 난이도 관련 (힘들었다/쉬웠다)
        - "pain": 통증/불편함 관련
        - "preference": 선호도 관련 (좋았다/별로였다)
        - "general": 일반 피드백

        rating: 1-5 (1=매우 부정적, 5=매우 긍정적)
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

    def parse_and_save_response(response_text, original_text, routine_id)
      json_str = extract_json(response_text)
      data = JSON.parse(json_str)

      # Save feedback to database
      save_feedback(data, original_text, routine_id)

      {
        success: true,
        message: data["message"],
        insights: data["insights"] || [],
        adaptations: data["adaptations"] || [],
        next_workout_recommendations: data["next_workout_recommendations"] || [],
        affected_exercises: data["affected_exercises"] || [],
        affected_muscles: data["affected_muscles"] || []
      }
    rescue JSON::ParserError => e
      Rails.logger.error("FeedbackService JSON parse error: #{e.message}")
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

    def save_feedback(data, original_text, routine_id)
      user.workout_feedbacks.create!(
        feedback: original_text,
        feedback_type: data["feedback_type"] || "general",
        rating: data["rating"] || 3,
        suggestions: data["adaptations"] || [],
        routine_id: routine_id,
        would_recommend: (data["rating"] || 3) >= 3
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("FeedbackService: Failed to save feedback: #{e.message}")
    end

    def mock_response
      {
        success: true,
        message: "피드백 감사해요! 다음 루틴에 반영할게요. 💡",
        insights: ["피드백이 기록되었습니다"],
        adaptations: ["다음 루틴에 반영 예정"],
        next_workout_recommendations: []
      }
    end
  end
end
