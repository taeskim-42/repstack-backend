# frozen_string_literal: true

require_relative "constants"
require_relative "llm_gateway"

module AiTrainer
  # Analyzes user condition from natural language text
  # Routes to cost-efficient models via LLM Gateway
  class ConditionService
    include Constants

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
      prompt = build_prompt(text)
      response = LlmGateway.chat(prompt: prompt, task: :condition_check)

      if response[:success]
        parse_response(response[:content], text)
      else
        mock_response
      end
    rescue StandardError => e
      Rails.logger.error("ConditionService error: #{e.message}")
      { success: false, error: "컨디션 분석 실패: #{e.message}" }
    end

    # For CheckCondition mutation - structured input returns adaptations
    def analyze_from_input(input)
      prompt = build_input_prompt(input)
      response = LlmGateway.chat(prompt: prompt, task: :condition_check)

      if response[:success]
        parse_input_response(response[:content])
      else
        mock_input_response(input)
      end
    rescue StandardError => e
      Rails.logger.error("ConditionService.analyze_from_input error: #{e.message}")
      { success: false, error: "컨디션 분석 실패: #{e.message}" }
    end

    # For CheckConditionFromVoice mutation - voice input returns condition + adaptations
    def analyze_from_voice(text)
      prompt = build_voice_prompt(text)
      response = LlmGateway.chat(prompt: prompt, task: :condition_check)

      if response[:success]
        parse_voice_response(response[:content])
      else
        mock_voice_response(text)
      end
    rescue StandardError => e
      Rails.logger.error("ConditionService.analyze_from_voice error: #{e.message}")
      { success: false, error: "음성 컨디션 분석 실패: #{e.message}" }
    end

    private

    attr_reader :user

    def build_prompt(text)
      <<~PROMPT
        당신은 전문 피트니스 트레이너입니다. 사용자가 말한 컨디션 상태를 분석하세요.

        ## 예시 (few-shot)
        - "구웃" → 좋음 (energy 4)
        - "구우웃" → 좋음 (energy 4)
        - "굿" → 좋음 (energy 4)
        - "최고" → 매우 좋음 (energy 5)
        - "쏘쏘" → 보통 (energy 3)
        - "ㅠㅠ" → 안좋음 (energy 2)
        - "피곤" → 안좋음 (energy 2)

        사용자 입력: "#{text}"

        아래 항목들을 1-5 점수로 평가하고 운동 조언을 제공하세요:
        - energy_level: 에너지 수준 (5=최상, 1=최하)
        - stress_level: 스트레스 (5=매우 높음, 1=없음)
        - sleep_quality: 수면 품질 (5=최상, 1=최하)
        - motivation: 운동 의욕 (5=최상, 1=최하)
        - soreness: 근육통 (5=매우 심함, 1=없음)

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
      retry_condition_response
    end

    def retry_condition_response
      {
        success: true,
        score: nil,
        status: "unknown",
        message: "컨디션을 잘 이해하지 못했어요. 다시 한번 말씀해 주시겠어요? 예: '오늘 좀 피곤해요' 또는 '컨디션 좋아요!'",
        adaptations: [],
        recommendations: [],
        parsed_condition: nil,
        needs_retry: true
      }
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
      {
        success: true,
        adaptations: ["컨디션 분석을 다시 시도해주세요"],
        intensity_modifier: 1.0,
        duration_modifier: 1.0,
        exercise_modifications: [],
        rest_recommendations: [],
        needs_retry: true
      }
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
        사용자의 오늘 컨디션: "#{text}"

        JSON으로 응답:
        ```json
        {
          "condition": {
            "energyLevel": 1-5,
            "stressLevel": 1-5,
            "sleepQuality": 1-5,
            "motivation": 1-5,
            "soreness": null,
            "availableTime": 60,
            "notes": null
          },
          "adaptations": [],
          "intensityModifier": 0.5-1.5,
          "durationModifier": 0.7-1.3,
          "exerciseModifications": [],
          "restRecommendations": [],
          "interpretation": "해석"
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
      {
        success: true,
        condition: {
          energy_level: 3,
          stress_level: 3,
          sleep_quality: 3,
          motivation: 3,
          soreness: nil,
          available_time: 60,
          notes: nil
        },
        adaptations: ["컨디션을 다시 말씀해 주세요"],
        intensity_modifier: 1.0,
        duration_modifier: 1.0,
        exercise_modifications: [],
        rest_recommendations: [],
        interpretation: "컨디션을 잘 이해하지 못했어요. 다시 한번 말씀해 주시겠어요?",
        needs_retry: true
      }
    end

    def mock_voice_response(text)
      # Simple rule-based fallback when LLM fails
      condition = parse_condition_from_text(text)

      {
        success: true,
        condition: condition,
        adaptations: build_adaptations_from_condition(condition),
        intensity_modifier: calculate_intensity_modifier(condition),
        duration_modifier: calculate_duration_modifier(condition),
        exercise_modifications: build_exercise_modifications(condition),
        rest_recommendations: build_rest_recommendations(condition),
        interpretation: "컨디션을 확인했습니다."
      }
    end

    def parse_condition_from_text(text)
      text_lower = text.downcase

      energy = 3
      stress = 3
      sleep_quality = 3
      motivation = 3
      soreness = nil

      # Energy detection
      if text_lower.match?(/피곤|지쳤|힘들|tired|exhausted|졸려/)
        energy = 2
      elsif text_lower.match?(/좋아|괜찮|good|great|최고|에너지/)
        energy = 4
      end

      # Stress detection
      if text_lower.match?(/스트레스|짜증|힘들|stressed/)
        stress = 4
      end

      # Sleep detection
      if text_lower.match?(/못 ?잤|잠을 ?못|수면|불면|잠이 ?안/)
        sleep_quality = 2
      elsif text_lower.match?(/푹 ?잤|잘 ?잤|숙면/)
        sleep_quality = 4
      end

      # Soreness detection
      if text_lower.match?(/어깨.*아파|어깨.*통증|shoulder/)
        soreness = { "shoulder" => 3 }
      elsif text_lower.match?(/허리.*아파|허리.*통증|back/)
        soreness = { "back" => 3 }
      elsif text_lower.match?(/다리.*아파|다리.*통증|leg/)
        soreness = { "legs" => 3 }
      end

      {
        energy_level: energy,
        stress_level: stress,
        sleep_quality: sleep_quality,
        motivation: motivation,
        soreness: soreness,
        available_time: 60,
        notes: nil
      }
    end

    def build_adaptations_from_condition(condition)
      adaptations = []
      adaptations << "운동 강도를 낮추세요" if condition[:energy_level] < 3
      adaptations << "휴식을 충분히 취하세요" if condition[:stress_level] > 3
      adaptations << "워밍업을 충분히 하세요" if condition[:sleep_quality] < 3
      adaptations << "평소 강도로 운동 가능합니다" if adaptations.empty?
      adaptations
    end

    def calculate_intensity_modifier(condition)
      base = 1.0
      base -= 0.1 if condition[:energy_level] < 3
      base -= 0.1 if condition[:stress_level] > 3
      base -= 0.1 if condition[:sleep_quality] < 3
      [base, 0.7].max
    end

    def calculate_duration_modifier(condition)
      base = 1.0
      base -= 0.1 if condition[:energy_level] < 3
      base -= 0.05 if condition[:sleep_quality] < 3
      [base, 0.8].max
    end

    def build_rest_recommendations(condition)
      recs = []
      recs << "세트 간 휴식을 늘리세요" if condition[:stress_level] > 3
      recs << "운동 후 스트레칭을 하세요" if condition[:soreness]
      recs
    end

    def build_exercise_modifications(condition)
      mods = []
      return mods unless condition[:soreness]

      condition[:soreness].each do |part, _level|
        case part.to_s
        when "shoulder"
          mods << "어깨 운동 제외"
        when "back"
          mods << "허리 운동 제외"
        when "legs"
          mods << "다리 운동 제외"
        end
      end
      mods
    end
  end
end
