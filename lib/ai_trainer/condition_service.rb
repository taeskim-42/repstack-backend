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
      # For ChatService - returns chat-friendly response
      def analyze_from_text(user:, text:)
        new(user: user).analyze_from_text(text)
      end

      # For CheckCondition mutation - structured input
      def analyze_from_input(user:, input:)
        new(user: user).analyze_from_input(input)
      end

      # For CheckConditionFromVoice mutation - voice input with condition parsing
      def analyze_from_voice(user:, text:)
        new(user: user).analyze_from_voice(text)
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

    # For CheckCondition mutation - structured input returns adaptations
    def analyze_from_input(input)
      return mock_input_response(input) unless api_configured?

      prompt = build_input_prompt(input)
      response = call_claude_api(prompt)
      parse_input_response(response)
    rescue StandardError => e
      Rails.logger.error("ConditionService.analyze_from_input error: #{e.message}")
      { success: false, error: "컨디션 분석 실패: #{e.message}" }
    end

    # For CheckConditionFromVoice mutation - voice input returns condition + adaptations
    def analyze_from_voice(text)
      return mock_voice_response(text) unless api_configured?

      prompt = build_voice_prompt(text)
      response = call_claude_api(prompt)
      parse_voice_response(response)
    rescue StandardError => e
      Rails.logger.error("ConditionService.analyze_from_voice error: #{e.message}")
      { success: false, error: "음성 컨디션 분석 실패: #{e.message}" }
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
        adaptations: [ "평소 강도로 운동 가능" ],
        recommendations: [ "충분한 수분 섭취", "운동 전 워밍업 필수" ]
      }
    end

    # === analyze_from_input helpers ===

    def build_input_prompt(input)
      <<~PROMPT
        You are an expert fitness coach. Based on the user's current condition, provide workout adaptations.

        Current Condition:
        - Energy Level: #{input[:energy_level]}/5
        - Stress Level: #{input[:stress_level]}/5
        - Sleep Quality: #{input[:sleep_quality]}/5
        - Motivation: #{input[:motivation]}/5
        - Available Time: #{input[:available_time]} minutes
        - Muscle Soreness: #{input[:soreness]&.to_json || "None reported"}
        - Notes: #{input[:notes] || "None"}

        Respond ONLY with valid JSON in this exact format:
        ```json
        {
          "adaptations": ["adaptation1", "adaptation2"],
          "intensityModifier": 0.5-1.5,
          "durationModifier": 0.7-1.3,
          "exerciseModifications": ["modification1", "modification2"],
          "restRecommendations": ["rest1", "rest2"]
        }
        ```
      PROMPT
    end

    def parse_input_response(response_text)
      json_str = extract_json(response_text)
      data = JSON.parse(json_str)

      {
        success: true,
        adaptations: data["adaptations"] || [],
        intensity_modifier: data["intensityModifier"] || 1.0,
        duration_modifier: data["durationModifier"] || 1.0,
        exercise_modifications: data["exerciseModifications"] || [],
        rest_recommendations: data["restRecommendations"] || []
      }
    rescue JSON::ParserError => e
      Rails.logger.error("ConditionService parse_input_response error: #{e.message}")
      { success: false, error: "응답 파싱 실패" }
    end

    def mock_input_response(input)
      energy = input[:energy_level] || 3
      stress = input[:stress_level] || 3
      sleep = input[:sleep_quality] || 3

      avg_condition = (energy + (6 - stress) + sleep) / 3.0
      intensity_modifier = 0.5 + (avg_condition / 5.0) * 0.5
      duration_modifier = 0.7 + (avg_condition / 5.0) * 0.3

      adaptations = []
      adaptations << "운동 강도를 낮추세요" if energy < 3
      adaptations << "스트레스 해소 운동을 포함하세요" if stress > 3
      adaptations << "운동 시간을 줄이세요" if sleep < 3
      adaptations << "평소 강도로 운동 가능" if adaptations.empty?

      {
        success: true,
        adaptations: adaptations,
        intensity_modifier: intensity_modifier.round(2),
        duration_modifier: duration_modifier.round(2),
        exercise_modifications: [],
        rest_recommendations: stress > 3 ? [ "세트 사이 휴식을 늘리세요" ] : []
      }
    end

    # === analyze_from_voice helpers ===

    def build_voice_prompt(text)
      <<~PROMPT
        You are an expert fitness coach. The user describes their current condition via voice.
        Understand their condition and provide workout adaptations.

        User's voice input (Korean or English):
        "#{text}"

        Based on what the user said, determine:
        1. Their overall condition (energy, stress, sleep, motivation, any soreness)
        2. Appropriate workout adaptations

        Respond ONLY with valid JSON in this exact format:
        ```json
        {
          "condition": {
            "energyLevel": 1-5,
            "stressLevel": 1-5,
            "sleepQuality": 1-5,
            "motivation": 1-5,
            "soreness": {"bodyPart": level} or null,
            "availableTime": minutes (default 60),
            "notes": "any additional notes"
          },
          "adaptations": ["adaptation1", "adaptation2"],
          "intensityModifier": 0.5-1.5,
          "durationModifier": 0.7-1.3,
          "exerciseModifications": ["modification1", "modification2"],
          "restRecommendations": ["rest1", "rest2"],
          "interpretation": "Brief explanation of how you interpreted the input"
        }
        ```
      PROMPT
    end

    def parse_voice_response(response_text)
      json_str = extract_json(response_text)
      data = JSON.parse(json_str)
      condition = data["condition"] || {}

      {
        success: true,
        condition: {
          energy_level: condition["energyLevel"] || 3,
          stress_level: condition["stressLevel"] || 3,
          sleep_quality: condition["sleepQuality"] || 3,
          motivation: condition["motivation"] || 3,
          soreness: condition["soreness"],
          available_time: condition["availableTime"] || 60,
          notes: condition["notes"]
        },
        adaptations: data["adaptations"] || [],
        intensity_modifier: data["intensityModifier"] || 1.0,
        duration_modifier: data["durationModifier"] || 1.0,
        exercise_modifications: data["exerciseModifications"] || [],
        rest_recommendations: data["restRecommendations"] || [],
        interpretation: data["interpretation"]
      }
    rescue JSON::ParserError => e
      Rails.logger.error("ConditionService parse_voice_response error: #{e.message}")
      { success: false, error: "응답 파싱 실패" }
    end

    def mock_voice_response(text)
      text_lower = text.downcase

      energy = 3
      stress = 3
      sleep_quality = 3
      motivation = 3
      soreness = nil

      # Korean keywords
      energy = 2 if text_lower.include?("피곤") || text_lower.include?("힘들") || text_lower.include?("지쳤")
      energy = 4 if text_lower.include?("좋아") || text_lower.include?("괜찮") || text_lower.include?("컨디션 좋")
      energy = 5 if text_lower.include?("최고") || text_lower.include?("완벽")

      stress = 4 if text_lower.include?("스트레스")
      sleep_quality = 2 if text_lower.include?("잠") && (text_lower.include?("못") || text_lower.include?("안"))
      motivation = 4 if text_lower.include?("운동하고 싶") || text_lower.include?("하고 싶")

      # English keywords
      energy = 2 if text_lower.include?("tired") || text_lower.include?("exhausted")
      energy = 4 if text_lower.include?("good") || text_lower.include?("great")
      motivation = 4 if text_lower.include?("excited") || text_lower.include?("ready")

      # Soreness detection
      soreness_map = {}
      soreness_map["shoulder"] = 3 if text_lower.include?("어깨") || text_lower.include?("shoulder")
      soreness_map["back"] = 3 if text_lower.include?("허리") || text_lower.include?("등") || text_lower.include?("back")
      soreness_map["legs"] = 3 if text_lower.include?("다리") || text_lower.include?("leg")
      soreness = soreness_map.presence

      avg_condition = (energy + (6 - stress) + sleep_quality) / 3.0
      intensity_modifier = (0.5 + (avg_condition / 5.0) * 0.5).round(2)
      duration_modifier = (0.7 + (avg_condition / 5.0) * 0.3).round(2)

      adaptations = []
      adaptations << "운동 강도를 낮추세요" if energy < 3
      adaptations << "스트레스 해소 운동을 포함하세요" if stress > 3
      adaptations << "운동 시간을 줄이세요" if sleep_quality < 3
      adaptations << "오늘 컨디션에 맞는 운동을 추천합니다" if adaptations.empty?

      exercise_mods = []
      if soreness&.key?("shoulder")
        exercise_mods << "어깨 운동 제외"
        adaptations << "어깨 부위 운동을 피하세요"
      end

      {
        success: true,
        condition: {
          energy_level: energy,
          stress_level: stress,
          sleep_quality: sleep_quality,
          motivation: motivation,
          soreness: soreness,
          available_time: 60,
          notes: nil
        },
        adaptations: adaptations,
        intensity_modifier: intensity_modifier,
        duration_modifier: duration_modifier,
        exercise_modifications: exercise_mods,
        rest_recommendations: stress > 3 ? [ "세트 사이 휴식을 늘리세요" ] : [],
        interpretation: "음성 입력에서 키워드 기반으로 분석했습니다"
      }
    end
  end
end
