# frozen_string_literal: true

module AiTrainer
  module Condition
    module ResponseParser
      private

      def parse_response(response_text, _original_text)
        json_str = extract_json(response_text)
        data = JSON.parse(json_str)

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
          adaptations: [ "컨디션 분석을 다시 시도해주세요" ],
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
            energy_level: 3, stress_level: 3, sleep_quality: 3,
            motivation: 3, soreness: nil, available_time: 60, notes: nil
          },
          adaptations: [ "컨디션을 다시 말씀해 주세요" ],
          intensity_modifier: 1.0,
          duration_modifier: 1.0,
          exercise_modifications: [],
          rest_recommendations: [],
          interpretation: "컨디션을 잘 이해하지 못했어요. 다시 한번 말씀해 주시겠어요?",
          needs_retry: true
        }
      end

      def mock_voice_response(text)
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

        energy = 2 if text_lower.match?(/피곤|지쳤|힘들|tired|exhausted|졸려/)
        energy = 4 if text_lower.match?(/좋아|괜찮|good|great|최고|에너지/)
        stress = 4 if text_lower.match?(/스트레스|짜증|힘들|stressed/)
        sleep_quality = 2 if text_lower.match?(/못 ?잤|잠을 ?못|수면|불면|잠이 ?안/)
        sleep_quality = 4 if text_lower.match?(/푹 ?잤|잘 ?잤|숙면/)

        soreness = { "shoulder" => 3 } if text_lower.match?(/어깨.*아파|어깨.*통증|shoulder/)
        soreness = { "back" => 3 } if text_lower.match?(/허리.*아파|허리.*통증|back/)
        soreness = { "legs" => 3 } if text_lower.match?(/다리.*아파|다리.*통증|leg/)

        {
          energy_level: energy, stress_level: stress, sleep_quality: sleep_quality,
          motivation: motivation, soreness: soreness, available_time: 60, notes: nil
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
        [ base, 0.7 ].max
      end

      def calculate_duration_modifier(condition)
        base = 1.0
        base -= 0.1 if condition[:energy_level] < 3
        base -= 0.05 if condition[:sleep_quality] < 3
        [ base, 0.8 ].max
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
          when "shoulder" then mods << "어깨 운동 제외"
          when "back" then mods << "허리 운동 제외"
          when "legs" then mods << "다리 운동 제외"
          end
        end
        mods
      end
    end
  end
end
