# frozen_string_literal: true

module AiTrainer
  module Condition
    module PromptTemplates
      private

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

      def build_voice_prompt(text)
        <<~PROMPT
          당신은 전문 피트니스 트레이너입니다. 사용자가 말한 컨디션 상태를 분석하세요.

          ## 예시 (few-shot) - 반드시 참고하세요!
          - "구웃", "구우웃", "굿", "good" → 좋음 (energyLevel: 4, motivation: 4)
          - "최고", "완벽", "짱" → 매우 좋음 (energyLevel: 5, motivation: 5)
          - "쏘쏘", "그냥", "보통" → 보통 (energyLevel: 3, motivation: 3)
          - "ㅠㅠ", "별로", "안좋아" → 안좋음 (energyLevel: 2, motivation: 2)
          - "피곤", "지쳤어", "힘들어" → 피곤함 (energyLevel: 2, sleepQuality: 2)
          - "아파", "통증" → 부상 주의 (soreness 정보 포함)

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
    end
  end
end
